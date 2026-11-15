// search.json reader. Scalars via ThemeJson; boost-dirs is an array, read with json-glib.
namespace LumenSearch {
    public class SearchConfig {
        // No initialisers: statics of a never-instantiated class are not set up (class_init
        // never runs). load() assigns every field, so call it before reading.
        public static string[] boost_dirs;
        public static bool content;
        public static int width;
        public static string background;
        public static string text;
        public static string muted_text;
        public static string highlight;

        static string expand(string p) {
            if (p == "~") return Environment.get_home_dir();
            if (p.has_prefix("~/")) return Environment.get_home_dir() + p.substring(1);
            return p;
        }

        public static void load() {
            string[] dirs = {};
            UserDirectory[] special = { UserDirectory.DOCUMENTS, UserDirectory.DESKTOP,
                UserDirectory.DOWNLOAD, UserDirectory.PICTURES, UserDirectory.MUSIC, UserDirectory.VIDEOS };
            foreach (var d in special) {
                var p = Environment.get_user_special_dir(d);
                if (p != null) dirs += p;
            }
            var path = LumenCommon.Paths.search_json();
            var tj = new LumenCommon.ThemeJson(path);
            content = tj.get_bool("search.content", true);
            width = tj.get_int("search.width", 680);
            background = tj.get_str("search.background", "#2a2a2aee");
            text = tj.get_str("search.text", "#ffffff");
            muted_text = tj.get_str("search.muted-text", "#ffffff99");
            highlight = tj.get_str("search.highlight", "#4c9bffff");
            try {
                var parser = new Json.Parser();
                parser.load_from_file(path);
                var root = parser.get_root();
                if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                    var o = root.get_object();
                    var bd = o.get_member("search.boost-dirs");
                    if (bd != null && bd.get_node_type() == Json.NodeType.ARRAY) {
                        bd.get_array().foreach_element((a, i, n) => {
                            if (n.get_value_type() == typeof(string)) dirs += expand(n.get_string());
                        });
                    }
                }
            } catch (GLib.Error e) {
                // missing/invalid file means defaults
            }
            boost_dirs = dirs;
        }

        public static bool is_boosted(string path) {
            if (boost_dirs == null) return false;
            foreach (var d in boost_dirs) {
                if (path == d || path.has_prefix(d + "/")) return true;
            }
            return false;
        }
    }
}
