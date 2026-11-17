namespace Lumen {

    public errordomain ManifestError { MISSING_FIELD, BAD_ID, BAD_TYPE, API_MISMATCH }

    public enum ParamType {
        BOOL, INT, DOUBLE, STRING, ENUM, COLOR;

        public static ParamType? parse (string s) {
            switch (s) {
                case "bool":   return BOOL;
                case "int":    return INT;
                case "double": return DOUBLE;
                case "string": return STRING;
                case "enum":   return ENUM;
                case "color":  return COLOR;
                default:       return null;
            }
        }
    }

    public class ParamDef : GLib.Object {
        public string key = "";
        public ParamType kind = ParamType.STRING;
        public Json.Node? default_value = null;
        public double min = 0;
        public double max = 0;          // min == max ⇒ unbounded
        public string[] choices = {};
        public string label = "";
    }

    // <id>/manifest.json:
    // { "id": "tray-wedge", "name": "Wedge tray", "version": "1", "api": 1,
    //   "provides": ["tray.presenter"], "packages": ["gtk4"],
    //   "params": { "height": { "type": "int", "default": 320, "min": 100, "max": 800, "label": "Height" } } }
    public class Manifest : GLib.Object {
        public string id = "";
        public string name = "";
        public string version = "";
        public int api = 0;
        public string[] provides = {};
        public string[] packages = {};     // extra valac --pkg
        public GLib.GenericArray<ParamDef> parameters = new GLib.GenericArray<ParamDef> ();
        public string dir = "";

        public ParamDef? param (string key) {
            foreach (var p in parameters) if (p.key == key) return p;
            return null;
        }

        // Namespace every type in the extension must live in: "tray-wedge" → "TrayWedge".
        public string type_namespace () {
            var sb = new StringBuilder ();
            foreach (var part in id.split ("-")) {
                if (part.length == 0) continue;
                sb.append (part.substring (0, 1).up ());
                sb.append (part.substring (1));
            }
            return sb.str;
        }

        // C symbol prefix valac derives from type_namespace(): "tray-wedge" → "tray_wedge_".
        public string symbol_prefix () {
            return id.replace ("-", "_") + "_";
        }

        public static Manifest load (string dir) throws GLib.Error {
            var parser = new Json.Parser ();
            parser.load_from_file (Path.build_filename (dir, "manifest.json"));
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                throw new ManifestError.BAD_TYPE ("manifest.json is not an object");
            return parse (root.get_object (), dir);
        }

        public static Manifest parse (Json.Object o, string dir) throws ManifestError {
            var m = new Manifest ();
            m.dir = dir;
            m.id = req_string (o, "id");
            m.name = req_string (o, "name");
            m.version = req_string (o, "version");
            if (!o.has_member ("api")) throw new ManifestError.MISSING_FIELD ("missing \"api\"");
            m.api = (int) o.get_int_member ("api");

            if (!valid_id (m.id)) throw new ManifestError.BAD_ID ("bad id \"%s\" (want ^[a-z][a-z0-9-]*$)", m.id);
            if (m.api != API_VERSION)
                throw new ManifestError.API_MISMATCH ("%s wants api %d, host has %d", m.id, m.api, API_VERSION);

            m.provides = string_array (o, "provides");
            m.packages = string_array (o, "packages");

            if (o.has_member ("params")) {
                var po = o.get_object_member ("params");
                if (po == null) throw new ManifestError.BAD_TYPE ("\"params\" must be an object");
                foreach (var key in po.get_members ()) {
                    var d = po.get_object_member (key);
                    if (d == null) throw new ManifestError.BAD_TYPE ("param %s must be an object", key);
                    var p = new ParamDef ();
                    p.key = key;
                    var kind = ParamType.parse (d.get_string_member_with_default ("type", ""));
                    if (kind == null) throw new ManifestError.BAD_TYPE ("param %s: unknown type", key);
                    p.kind = kind;
                    p.default_value = d.has_member ("default") ? d.get_member ("default").copy () : null;
                    p.min = d.get_double_member_with_default ("min", 0);
                    p.max = d.get_double_member_with_default ("max", 0);
                    p.choices = string_array (d, "choices");
                    p.label = d.get_string_member_with_default ("label", key);
                    m.parameters.add (p);
                }
            }
            return m;
        }

        static bool valid_id (string id) {
            if (id.length == 0 || !(id[0] >= 'a' && id[0] <= 'z')) return false;
            for (int i = 0; i < id.length; i++) {
                char c = id[i];
                if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')) return false;
            }
            return true;
        }

        static string req_string (Json.Object o, string key) throws ManifestError {
            if (!o.has_member (key)) throw new ManifestError.MISSING_FIELD ("missing \"%s\"", key);
            var n = o.get_member (key);
            if (n.get_value_type () != typeof (string))
                throw new ManifestError.BAD_TYPE ("\"%s\" must be a string", key);
            return n.get_string ();
        }
    }

    // Shared by Manifest and ExtensionConfig; non-string elements are skipped.
    internal string[] string_array (Json.Object o, string key) {
        string[] out_ = {};
        if (!o.has_member (key)) return out_;
        var arr = o.get_array_member (key);
        if (arr == null) return out_;
        arr.foreach_element ((a, i, n) => {
            if (n.get_value_type () == typeof (string)) out_ += n.get_string ();
        });
        return out_;
    }
}
