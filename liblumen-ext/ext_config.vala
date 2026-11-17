namespace Lumen {

    // ~/.config/lumen-shell/extensions.json:
    // { "disabled": ["tray-wedge"],
    //   "slots":    { "tray.presenter": "tray-wedge" },
    //   "params":   { "tray-wedge": { "height": 400 } } }
    // A missing or broken file means all defaults.
    public class ExtensionConfig : GLib.Object {
        string[] disabled = {};
        Json.Object slots = new Json.Object ();
        Json.Object params_ = new Json.Object ();

        public static ExtensionConfig load (string path) {
            var c = new ExtensionConfig ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return c;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT)
                    c.parse (root.get_object ());
            } catch (GLib.Error e) {
                warning ("lumen-ext: ignoring %s: %s", path, e.message);
            }
            return c;
        }

        public static ExtensionConfig from_json (string json) {
            var c = new ExtensionConfig ();
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT)
                    c.parse (root.get_object ());
            } catch (GLib.Error e) {
                warning ("lumen-ext: bad extensions config: %s", e.message);
            }
            return c;
        }

        void parse (Json.Object o) {
            disabled = string_array (o, "disabled");
            var s = o.has_member ("slots") ? o.get_object_member ("slots") : null;
            if (s != null) slots = s;
            var p = o.has_member ("params") ? o.get_object_member ("params") : null;
            if (p != null) params_ = p;
        }

        public bool is_enabled (string id) {
            return !(id in disabled);
        }

        public string? active_for (string slot) {
            if (!slots.has_member (slot)) return null;
            var n = slots.get_member (slot);
            return n.get_value_type () == typeof (string) ? n.get_string () : null;
        }

        public Json.Node? param (string ext_id, string key) {
            if (!params_.has_member (ext_id)) return null;
            var o = params_.get_object_member (ext_id);
            return (o != null && o.has_member (key)) ? o.get_member (key) : null;
        }
    }
}
