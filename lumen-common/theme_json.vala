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
}
