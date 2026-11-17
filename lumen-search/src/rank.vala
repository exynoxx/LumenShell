// Scores indexed items against a Query and splits them into sections.
namespace LumenSearch {
    public enum ItemKind { APP, FILE, FOLDER }

    public class Item : GLib.Object {
        public ItemKind kind;
        public string name = "";
        public string dir = "";          // "" for apps
        public string uri = "";
        public string mime = "";
        public int64 recent_age_s = -1;
        public bool junk;
        public bool boosted;
        public GLib.AppInfo? app;
        public string[] extra = {};      // app generic name + keywords
    }

    public class Hit : GLib.Object {
        public Item item;
        public int score;
        public int[] name_pos = {};
        public int[] dir_pos = {};
        public string? snippet_markup;
    }

    public class Results {
        public Hit? top;
        public Hit[] apps = {};
        public Hit[] files = {};
    }

    public class Ranker {
        const int MAX_APPS = 5;
        const int MAX_FILES = 8;

        Item[] items = {};
        // Incremental cache: candidates (indices into items) that matched last_raw.
        string? last_raw;
        string last_filter = "";
        int[] last_cands = {};

        public void set_items(Item[] new_items) {
            items = new_items;
            last_raw = null;
            last_cands = {};
        }

        // junk strictly last, then best score first, name as a stable tie-break.
        public static int compare_hits(Hit a, Hit b) {
            int ja = a.item.junk ? 1 : 0, jb = b.item.junk ? 1 : 0;
            if (ja != jb) return ja - jb;
            if (a.score != b.score) return b.score - a.score;
            return GLib.strcmp(a.item.name, b.item.name);
        }

        static string filter_sig(Query q) {
            return string.joinv("|", q.mime_prefixes) + (q.apps_only ? "A" : "a") + (q.hide_apps ? "H" : "h");
        }

        static void add_pos(ref int[] dst, int[] src) {
            int[] r = dst;
            foreach (var p in src) if (!(p in r)) r += p;
            dst = r;
        }

        // Best single path segment (below $HOME when under it); positions are byte offsets in dir.
        static bool match_dir(string term, string dir, out int score, out int[] pos) {
            score = 0; pos = {};
            int start = 0;
            string home = Environment.get_home_dir();
            if (dir == home) return false;
            if (dir.has_prefix(home + "/")) start = home.length;
            bool found = false;
            while (start < dir.length) {
                if (dir[start] == '/') { start++; continue; }
                int end = dir.index_of_char('/', start);
                if (end < 0) end = dir.length;
                int s; int[] p;
                if (Fuzzy.match(term, dir.substring(start, end - start), out s, out p) && (!found || s > score)) {
                    found = true; score = s;
                    pos = p;
                    for (int i = 0; i < pos.length; i++) pos[i] += start;
                }
                start = end;
            }
            return found;
        }

        // Every term must match name (x1), dir (x0.5) or app extra (x0.7).
        static Hit? score_item(Item it, Query q) {
            if (it.kind == ItemKind.APP) {
                if (q.hide_apps) return null;
            } else if (q.apps_only || !q.matches_mime(it.mime)) {
                return null;
            }
            double sum = 0;
            int[] npos = {};
            int[] dpos = {};
            foreach (var term in q.terms) {
                int s; int[] p;
                if (Fuzzy.match(term, it.name, out s, out p)) {
                    sum += s;
                    add_pos(ref npos, p);
                    continue;
                }
                if (it.kind != ItemKind.APP) {
                    if (match_dir(term, it.dir, out s, out p)) {
                        sum += s * 0.5;
                        add_pos(ref dpos, p);
                        continue;
                    }
                    return null;
                }
                bool ok = false;
                foreach (var e in it.extra) {
                    if (Fuzzy.match(term, e, out s, out p)) {
                        sum += s * 0.7;
                        ok = true;
                        break;
                    }
                }
                if (!ok) return null;
            }
            double w = it.kind == ItemKind.APP ? 1.5 : (it.kind == ItemKind.FILE ? 1.0 : 0.9);
            double loc = it.boosted ? 40 : 0;
            double rec = 0;
            if (it.recent_age_s >= 0) {
                if (it.recent_age_s < 86400) rec = 60;
                else if (it.recent_age_s < 7 * 86400) rec = 30;
                else if (it.recent_age_s < 30 * 86400) rec = 10;
            }
            var h = new Hit();
            h.item = it;
            h.score = (int) (sum * w + loc + rec + 0.5);
            h.name_pos = npos;
            h.dir_pos = dpos;
            return h;
        }

        public Results search(Query q) {
            // Appending only tightens the AND-of-fuzzy match, so last time's
            // matches are a superset of this time's (same type filter required).
            string sig = filter_sig(q);
            bool incremental = last_raw != null && q.raw.has_prefix(last_raw) && sig == last_filter;
            Hit[] hits = {};
            int[] cands = {};
            // ponytail: full rescan per new query; chunk on a worker thread if indexes exceed ~50k
            if (incremental) {
                foreach (var i in last_cands) {
                    var h = score_item(items[i], q);
                    if (h != null) { hits += h; cands += i; }
                }
            } else {
                for (int i = 0; i < items.length; i++) {
                    var h = score_item(items[i], q);
                    if (h != null) { hits += h; cands += i; }
                }
            }
            last_raw = q.raw;
            last_filter = sig;
            last_cands = cands;
            return build(hits, q);
        }

        // A lone weak match must not become Top Hit; type-only queries have no terms and no floor.
        static double min_top_score(Query q) {
            int chars = 0;
            foreach (var t in q.terms) chars += t.char_count();
            return 20.0 * chars;
        }

        static Results build(owned Hit[] hits, Query q) {
            var res = new Results();
            Hit[] apps = {};
            Hit[] files = {};
            foreach (var h in hits) {
                if (h.item.kind == ItemKind.APP) apps += h; else files += h;
            }
            GLib.qsort_with_data<Hit>(apps, sizeof(Hit), (a, b) => compare_hits(a, b));
            GLib.qsort_with_data<Hit>(files, sizeof(Hit), (a, b) => compare_hits(a, b));

            // Top: best non-junk across both sections, if clearly ahead.
            Hit? best = null, second = null;
            bool best_is_app = false;
            Hit[] nj = {};
            foreach (var h in hits) if (!h.item.junk) nj += h;
            foreach (var h in nj) {
                if (best == null || compare_hits(h, best) < 0) { second = best; best = h; }
                else if (second == null || compare_hits(h, second) < 0) second = h;
            }
            if (best != null && (second == null || best.score >= 1.2 * second.score && best.score > second.score)
                && best.score >= min_top_score(q)) {
                res.top = best;
                best_is_app = best.item.kind == ItemKind.APP;
            }
            res.apps = take(apps, MAX_APPS, best_is_app ? res.top : null);
            res.files = take(files, MAX_FILES, best_is_app ? null : res.top);
            return res;
        }

        static Hit[] take(Hit[] sorted, int max, Hit? skip) {
            Hit[] o = {};
            foreach (var h in sorted) {
                if (h == skip) continue;
                if (o.length >= max) break;
                o += h;
            }
            return o;
        }
    }
}
