using GLib;
using Json;

public class Theme : GLib.Object {

    // Default palette mirrors default-theme.json; load_from_file() overwrites if JSON is found.
    static GLib.HashTable<string, string> palette;

    static void seed_defaults () {
        palette = new GLib.HashTable<string, string>(str_hash, str_equal);
        palette.insert("panel_background",      "rgba(0,0,0,0)");
        palette.insert("tray_background",       "rgba(17,20,31,0.97)");
        palette.insert("tray_icon_hover",       "rgba(41,46,66,1)");
        palette.insert("app_hover",             "rgba(255,255,255,0.20)");
        palette.insert("app_launching",         "rgba(250,168,51,1)");
        palette.insert("app_active_underline",  "rgba(0,44,230,1)");
        // Auto-hide backdrop: same color as the panel by default, but its own
        // alpha (settings keeps the RGB synced to panel.background).
        palette.insert("panel_autohide_background", "rgba(26,29,39,0.5)");
    }

    static string key_to_var (string json_key) {
        return json_key.replace(".", "_").replace("-", "_");
    }

    static void load_from_file () {
        var path = Utils.THEME_FILE;
        if (!FileUtils.test(path, FileTest.EXISTS)) return;
        var parser = new Json.Parser();
        try {
            parser.load_from_file(path);
        } catch (Error e) {
            stderr.printf("Theme load failed: %s\n", e.message);
            return;
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return;
        root.get_object().foreach_member((obj, name, node) => {
            if (node.get_value_type() != typeof(string)) return;
            var rgba = Gdk.RGBA();
            if (!rgba.parse(node.get_string())) return;
            palette.insert(key_to_var(name), rgba.to_string());
        });
    }

    // Resolve a raw color value (for code paths that draw with Gdk.RGBA instead
    // of CSS, where @-references don't apply). Falls back to `fallback` if the
    // key is absent or unparseable. Palette is seeded by install() at startup.
    public static Gdk.RGBA color (string json_key, string fallback) {
        var rgba = Gdk.RGBA();
        string? v = (palette != null) ? palette.lookup(key_to_var(json_key)) : null;
        if (v == null || !rgba.parse(v)) rgba.parse(fallback);
        return rgba;
    }

    static string build_define_color_block () {
        var sb = new StringBuilder();
        palette.foreach((k, v) => {
            sb.append_printf("@define-color %s %s;\n", k, v);
        });
        return sb.str;
    }

    public static void install () {
        seed_defaults();
        load_from_file();

        var provider = new Gtk.CssProvider();
        try {
            var bytes = resources_lookup_data("/dev/lumen/panel/style.css",
                ResourceLookupFlags.NONE);
            var base_css = (string) bytes.get_data();
            var combined = build_define_color_block() + "\n" + base_css;
            provider.load_from_string(combined);
        } catch (Error e) {
            stderr.printf("Theme: failed to load embedded CSS: %s\n", e.message);
            return;
        }
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}
