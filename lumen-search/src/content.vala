// Full-text content search through LocalSearch's FTS index.
namespace LumenSearch {
    public class ContentSearch {
        const int MAX_SHOWN = 5;
        const string SPARQL = "SELECT ?u fts:snippet(?c, \"\\u0002\", \"\\u0003\", \"…\", 8) ?m WHERE { " +
            "?c fts:match ~q ; nie:isStoredAs ?f . ?f nie:url ?u . OPTIONAL { ?c nie:mimeType ?m } } " +
            "ORDER BY DESC(fts:rank(?c)) LIMIT 20";

        // Each term reduced to [\w]+ with a prefix star; type words are not in q.terms.
        public static string? fts_input(Query q) {
            string[] parts = {};
            int chars = 0;
            foreach (var t in q.terms) {
                var sb = new StringBuilder();
                for (int i = 0; i < t.length; ) {
                    var ch = t.get_char(i);
                    i += ch.to_string().length;
                    if (ch.isalnum() || ch == '_') { sb.append_unichar(ch); chars++; }
                }
                if (sb.len > 0) parts += sb.str + "*";
            }
            return chars < 3 ? null : string.joinv(" ", parts);
        }

        static string markup(string snip) {
            // escape_text turns the control-char markers into &#x2;/&#x3; entities.
            return Markup.escape_text(snip).replace("&#x2;", "<b>").replace("&#x3;", "</b>");
        }

        public async Hit[] run(Query q, Cancellable? c) throws GLib.Error {
            Hit[] hits = {};
            if (q.apps_only || !SearchConfig.content) return hits;
            var input = fts_input(q);
            var conn = LocalSearch.connection();
            if (input == null || conn == null) return hits;
            var stmt = conn.query_statement(SPARQL, c);
            stmt.bind_string("q", input);
            var cur = yield stmt.execute_async(c);
            var home = Environment.get_home_dir();
            int rank = 0;
            while (yield cur.next_async(c)) {
                var mime = cur.get_string(2) ?? "";
                if (!q.matches_mime(mime)) continue;
                var it = LocalSearch.item_from(cur.get_string(0) ?? "", mime, home);
                if (it == null) continue;
                var h = new Hit();
                h.item = it;
                h.score = 1000 - rank++;   // keeps FTS order within a tier
                h.snippet_markup = markup((cur.get_string(1) ?? "").make_valid());
                hits += h;
            }
            cur.close();
            GLib.qsort_with_data<Hit>(hits, sizeof(Hit), (a, b) => Ranker.compare_hits(a, b));
            if (hits.length > MAX_SHOWN) hits = hits[0:MAX_SHOWN];
            return hits;
        }
    }
}
