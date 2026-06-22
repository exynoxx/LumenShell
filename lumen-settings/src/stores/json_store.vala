namespace LumenSettings {

    /* Tiny dotted-key JSON store. Values are stored as strings (or int64); the
     * existing per-app loaders accept both. Reads tolerate a missing file. */
    public class JsonStore : GLib.Object {
        public string path { get; construct; }
        GLib.HashTable<string, Json.Node> values =
            new GLib.HashTable<string, Json.Node>(str_hash, str_equal);

        public JsonStore(string path) {
            GLib.Object(path: path);
            load();
        }

        public string? get_string(string key) {
            var n = values.lookup(key);
            if (n == null || n.get_value_type() != typeof(string)) return null;
            return n.get_string();
        }

        public int64 get_int(string key, int64 fallback) {
            var n = values.lookup(key);
            if (n == null || n.get_value_type() != typeof(int64)) return fallback;
            return n.get_int();
        }

        public void set_string(string key, string val) {
            var n = new Json.Node(Json.NodeType.VALUE);
            n.set_string(val);
            values.insert(key, n);
        }

        public void set_int(string key, int64 val) {
            var n = new Json.Node(Json.NodeType.VALUE);
            n.set_int(val);
            values.insert(key, n);
        }

        public bool get_bool(string key, bool fallback) {
            var n = values.lookup(key);
            if (n == null || n.get_value_type() != typeof(bool)) return fallback;
            return n.get_boolean();
        }

        public void set_bool(string key, bool val) {
            var n = new Json.Node(Json.NodeType.VALUE);
            n.set_boolean(val);
            values.insert(key, n);
        }

        /* String-array accessors (e.g. the panel's tray order/disabled lists).
         * Non-array / missing keys read as an empty array; only string elements
         * are kept. */
        public string[] get_string_array(string key) {
            string[] result = {};
            var n = values.lookup(key);
            if (n == null || n.get_node_type() != Json.NodeType.ARRAY) return result;
            foreach (var elem in n.get_array().get_elements()) {
                if (elem.get_node_type() != Json.NodeType.VALUE) continue;
                if (elem.get_value_type() != typeof(string)) continue;
                result += elem.get_string();
            }
            return result;
        }

        public void set_string_array(string key, string[] vals) {
            var arr = new Json.Array();
            foreach (var v in vals) arr.add_string_element(v);
            var n = new Json.Node(Json.NodeType.ARRAY);
            n.set_array(arr);
            values.insert(key, n);
        }

        public void save() {
            Paths.ensure_dir();
            var obj = new Json.Object();
            values.foreach((k, v) => { obj.set_member(k, v); });
            var root = new Json.Node(Json.NodeType.OBJECT);
            root.set_object(obj);
            var gen = new Json.Generator();
            gen.root = root;
            gen.pretty = true;
            try {
                gen.to_file(path);
            } catch (Error e) {
                stderr.printf("lumen-settings: JsonStore.save(%s): %s\n", path, e.message);
            }
        }

        void load() {
            if (!FileUtils.test(path, FileTest.EXISTS)) return;
            var parser = new Json.Parser();
            try {
                parser.load_from_file(path);
            } catch (Error e) {
                stderr.printf("lumen-settings: JsonStore.load(%s): %s\n", path, e.message);
                return;
            }
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return;
            root.get_object().foreach_member((obj, name, node) => {
                values.insert(name, node.copy());
            });
        }
    }
}
