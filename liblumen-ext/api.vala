namespace Lumen {

    // Bumped on any incompatible change to the public API; manifests declare
    // the version they were written against.
    public const int API_VERSION = 1;

    // An extension module exports `public Lumen.Extension lumen_extension_new ()`.
    // Extensions are loaded once and never unloaded, so there is no disable().
    public abstract class Extension : GLib.Object {
        public abstract void enable (Context ctx) throws GLib.Error;
    }

    public class Context : GLib.Object {
        public Manifest manifest { get; construct; }
        public Registry registry { get; construct; }
        public ExtensionConfig config { get; construct; }
        public Gtk.Application? app { get; construct; }

        public string id  { get { return manifest.id; } }
        public string dir { get { return manifest.dir; } }

        public Context (Manifest manifest, Registry registry,
                        ExtensionConfig config, Gtk.Application? app) {
            GLib.Object (manifest: manifest, registry: registry, config: config, app: app);
        }

        // Absolute path of a data file shipped beside the extension's sources.
        public string path (string rel) {
            return Path.build_filename (dir, rel);
        }

        public void provide (string slot, GLib.Object impl) {
            registry.provide (slot, id, impl);
        }

        // Undo every provide() — called by the host when enable() throws.
        public void release () {
            registry.withdraw (id);
        }

        // extensions.json value → manifest default, clamped to [min, max].
        public int param_int (string key) {
            return (int) param_double (key);
        }

        public double param_double (string key) {
            var def = manifest.param (key);
            var node = value_node (key);
            double v = 0;
            if (node != null && node.get_value_type () == typeof (int64))  v = node.get_int ();
            else if (node != null && node.get_value_type () == typeof (double)) v = node.get_double ();
            if (def != null && def.min < def.max) v = v.clamp (def.min, def.max);
            return v;
        }

        public bool param_bool (string key) {
            var node = value_node (key);
            return node != null && node.get_value_type () == typeof (bool) && node.get_boolean ();
        }

        public string param_string (string key) {
            var node = value_node (key);
            if (node != null && node.get_value_type () == typeof (string)) return node.get_string ();
            return "";
        }

        // Config value if it has the default's type, else the default.
        Json.Node? value_node (string key) {
            var def = manifest.param (key);
            var user = config.param (id, key);
            if (user != null && user.get_node_type () == Json.NodeType.VALUE) {
                if (def == null || def.default_value == null) return user;
                var dt = def.default_value.get_value_type ();
                var ut = user.get_value_type ();
                bool numeric = (dt == typeof (int64) || dt == typeof (double))
                            && (ut == typeof (int64) || ut == typeof (double));
                if (dt == ut || numeric) return user;
            }
            return def != null ? def.default_value : null;
        }
    }
}
