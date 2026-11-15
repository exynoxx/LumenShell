// Splits a raw search string into free terms plus type/app filters.
namespace LumenSearch {
    public class Query {
        public string raw;
        // Original case kept; smart-case is decided by the matcher.
        public string[] terms = {};
        // Union of MIME prefixes from type words; empty means no MIME filter.
        public string[] mime_prefixes = {};
        public bool apps_only;
        public bool hide_apps;

        public static Query parse(string raw) {
            var q = new Query();
            q.raw = raw;
            string[] terms = {};
            string[] mimes = {};
            foreach (var word in raw.split_set(" \t\n\r")) {
                if (word == "") continue;
                if (is_app_word(word)) {
                    q.apps_only = true;
                    continue;
                }
                var prefixes = Types.lookup(word);
                if (prefixes != null) {
                    foreach (var m in prefixes) mimes += m;
                    q.hide_apps = true;
                    continue;
                }
                terms += word;
            }
            q.terms = terms;
            q.mime_prefixes = mimes;
            return q;
        }

        public bool matches_mime(string mime) {
            if (mime_prefixes.length == 0) return true;
            foreach (var p in mime_prefixes) {
                if (mime.has_prefix(p)) return true;
            }
            return false;
        }

        static bool is_app_word(string word) {
            foreach (var a in Types.APP_WORDS) {
                if (word.down() == a) return true;
            }
            return false;
        }
    }
}
