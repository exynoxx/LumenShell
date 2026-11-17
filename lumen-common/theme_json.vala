// Flat-JSON reader for theme and config files (also panel.json, search.json).
// A missing or invalid file reads as empty, so every getter returns its default.
namespace LumenCommon {
    public class ThemeJson {
        private Json.Object? obj = null;

        public ThemeJson(string path) {
            if (!FileUtils.test(path, FileTest.EXISTS)) return;
            var parser = new Json.Parser();
            try {
                parser.load_from_file(path);
            } catch (Error e) {
                warning("theme load failed (%s): %s", path, e.message);
                return;
            }
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.OBJECT)
                obj = root.get_object();
        }

        // The whole document; empty when the file was missing or invalid.
        public Json.Object root() {
            return obj ?? new Json.Object();
        }

        public bool has(string key) {
            return obj != null && obj.has_member(key);
        }

        // String-array values, stripped, empties dropped; missing/non-array ⇒ {}.
        public string[] get_str_array(string key) {
            string[] r = {};
            if (!has(key)) return r;
            var n = obj.get_member(key);
            if (n.get_node_type() != Json.NodeType.ARRAY) return r;
            foreach (var e in n.get_array().get_elements()) {
                if (e.get_value_type() != typeof(string)) continue;
                var s = e.get_string().strip();
                if (s != "") r += s;
            }
            return r;
        }

        private Json.Node? member(string key, Type t) {
            if (obj == null || !obj.has_member(key)) return null;
            var n = obj.get_member(key);
            if (n.get_value_type() == t) return n;
            warning("theme key %s has the wrong type", key);
            return null;
        }

        public string get_str(string key, string def) {
            var n = member(key, typeof(string));
            return n != null ? n.get_string() : def;
        }

        public int get_int(string key, int def) {
            var n = member(key, typeof(int64));
            return n != null ? (int) n.get_int() : def;
        }

        public bool get_bool(string key, bool def) {
            var n = member(key, typeof(bool));
            return n != null ? n.get_boolean() : def;
        }

        // Any Gdk.RGBA.parse() spelling, for the value and the default alike.
        public Gdk.RGBA get_color(string key, string def) {
            var c = Gdk.RGBA();
            var n = member(key, typeof(string));
            if (n != null) {
                if (c.parse(n.get_string())) return c;
                warning("invalid color for %s: %s", key, n.get_string());
            }
            c.parse(def);
            return c;
        }
    }

    // Colours for stylesheets that read @define-color names. JSON keys map to
    // CSS names with . and - turned into _. `defaults` is {css-name, colour, ...};
    // every parseable string in the file overrides or adds to it.
    public class Palette {
        private HashTable<string, string> colors = new HashTable<string, string>(str_hash, str_equal);

        public Palette(string path, string[] defaults) {
            for (int i = 0; i + 1 < defaults.length; i += 2) colors.insert(defaults[i], defaults[i + 1]);
            new ThemeJson(path).root().foreach_member((o, name, node) => {
                if (node.get_value_type() != typeof(string)) return;
                var c = Gdk.RGBA();
                if (c.parse(node.get_string())) colors.insert(css_name(name), c.to_string());
            });
        }

        static string css_name(string key) {
            return key.replace(".", "_").replace("-", "_");
        }

        // For code that draws with Gdk.RGBA, where @-references don't apply.
        public Gdk.RGBA color(string json_key, string fallback) {
            var c = Gdk.RGBA();
            string? v = colors.lookup(css_name(json_key));
            if (v == null || !c.parse(v)) c.parse(fallback);
            return c;
        }

        public string define_colors() {
            var sb = new StringBuilder();
            colors.foreach((k, v) => sb.append_printf("@define-color %s %s;\n", k, v));
            return sb.str;
        }
    }
}
