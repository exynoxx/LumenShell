// LocalSearch connection, file index and app index.
namespace LumenSearch {
    public class LocalSearch {
        static Tsparql.SparqlConnection? conn;
        static bool tried;

        // One warning (no paths) on failure; null afterwards means files/contents stay empty.
        public static Tsparql.SparqlConnection? connection() {
            if (tried) return conn;
            tried = true;
            try {
                conn = Tsparql.SparqlConnection.bus_new("org.freedesktop.LocalSearch3", null, null);
            } catch (GLib.Error e) {
                warning("LocalSearch unavailable, file and content search disabled: %s", e.message);
            }
            return conn;
        }

        // GLib strings from URIs may be non-UTF-8; Fuzzy walks by char.
        public static Item? item_from(string uri, string mime, string home) {
            string path;
            try {
                path = Filename.from_uri(uri);
            } catch (GLib.Error e) {
                return null;
            }
            var it = new Item();
            it.uri = uri;
            it.mime = mime;
            it.kind = mime == "inode/directory" ? ItemKind.FOLDER : ItemKind.FILE;
            it.name = Filename.display_basename(path);
            it.dir = Filename.display_name(Path.get_dirname(path));
            it.junk = Junk.is_junk(path, home);
            it.boosted = SearchConfig.is_boosted(path);
            return it;
        }
    }

    public class FileIndex {
        const string SPARQL = "SELECT ?u ?m ?mod WHERE { ?f a nfo:FileDataObject ; nie:url ?u . " +
            "OPTIONAL { ?c nie:isStoredAs ?f ; nie:mimeType ?m } OPTIONAL { ?f nfo:fileLastModified ?mod } }";

        public async Item[] load(Cancellable? c) throws GLib.Error {
            Item[] items = {};
            var conn = LocalSearch.connection();
            if (conn == null) return items;
            var cur = yield conn.query_async(SPARQL, c);
            var home = Environment.get_home_dir();
            var seen = new HashTable<string, bool>(str_hash, str_equal);
            // ponytail: ~50k files held in memory; page/stream if the index grows far beyond that.
            while (yield cur.next_async(c)) {
                var u = cur.get_string(0);
                if (u == null || !u.has_prefix("file://") || seen.contains(u)) continue;
                seen[u] = true;
                var it = LocalSearch.item_from(u, cur.get_string(1) ?? "", home);
                if (it != null) items += it;
            }
            cur.close();
            join_recent(items);
            return items;
        }

        // Best effort: RecentManager needs GTK initialised (no display, no recency).
        static void join_recent(Item[] items) {
            if (!Gtk.init_check()) return;
            var ages = new HashTable<string, int64?>(str_hash, str_equal);
            var now = new DateTime.now_utc();
            foreach (var ri in Gtk.RecentManager.get_default().get_items()) {
                var t = ri.get_visited() ?? ri.get_modified();
                if (t != null) ages[ri.get_uri()] = (now.difference(t) / TimeSpan.SECOND).abs();
            }
            foreach (var it in items) {
                var a = ages[it.uri];
                if (a != null) it.recent_age_s = a;
            }
        }
    }

    public class AppIndex {
        public static Item[] load() {
            Item[] items = {};
            foreach (var a in AppInfo.get_all()) {
                if (!a.should_show()) continue;
                var it = new Item();
                it.kind = ItemKind.APP;
                it.name = a.get_name().make_valid();
                it.uri = a.get_id() ?? "";
                it.app = a;
                string[] extra = {};
                var d = a as DesktopAppInfo;
                if (d != null) {
                    var g = d.get_generic_name();
                    if (g != null) extra += g.make_valid();
                    foreach (var k in d.get_keywords()) extra += k.make_valid();
                }
                it.extra = extra;
                items += it;
            }
            return items;
        }
    }
}
