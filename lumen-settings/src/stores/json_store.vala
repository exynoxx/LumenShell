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
