using GLib;
using Json;

public class Theme : GLib.Object {

    public static string theme_file_path () {
        return Environment.get_variable("LUMEN_THEME_FILE")
            ?? "/usr/share/lumen-panel/default-theme.json";
    }

    // Default palette mirrors default-theme.json; load() overwrites if JSON is found.
    static GLib.HashTable<string, string> palette;

    static void seed_defaults () {
        palette = new GLib.HashTable<string, string>(str_hash, str_equal);
        palette.insert("panel_background",      "rgba(0,0,0,0)");
        palette.insert("tray_background",       "rgba(17,20,31,0.97)");
        palette.insert("tray_icon_hover",       "rgba(41,46,66,1)");
        palette.insert("app_hover",             "rgba(255,255,255,0.20)");
        palette.insert("app_launching",         "rgba(250,168,51,1)");
        palette.insert("app_active_underline",  "rgba(0,44,230,1)");
    }

    // Map JSON keys ("panel.background") to CSS variable names ("panel_background").
    static string key_to_var (string json_key) {
        return json_key.replace(".", "_").replace("-", "_");
    }

    static string? parse_hex_to_rgba (string hex_with_hash) {
        if (!hex_with_hash.has_prefix("#")) return null;
        string s = hex_with_hash.substring(1);
        if (s.length == 3 || s.length == 4) {
            var sb = new StringBuilder();
            for (int i = 0; i < s.length; i++) {
                sb.append_c(s[i]); sb.append_c(s[i]);
            }
            s = sb.str;
        }
        if (s.length != 6 && s.length != 8) return null;

        uint64 v = 0;
        for (int i = 0; i < s.length; i++) {
            char ch = s[i];
            uint64 nibble;
            if (ch >= '0' && ch <= '9')      nibble = ch - '0';
            else if (ch >= 'a' && ch <= 'f') nibble = ch - 'a' + 10;
            else if (ch >= 'A' && ch <= 'F') nibble = ch - 'A' + 10;
            else return null;
            v = (v << 4) | nibble;
        }

        int r, g, b;
        double a;
        if (s.length == 6) {
            r = (int) ((v >> 16) & 0xFF);
            g = (int) ((v >>  8) & 0xFF);
            b = (int) ( v        & 0xFF);
            a = 1.0;
        } else {
            r = (int) ((v >> 24) & 0xFF);
            g = (int) ((v >> 16) & 0xFF);
            b = (int) ((v >>  8) & 0xFF);
            a = ((v & 0xFF) / 255.0);
        }
        return "rgba(%d,%d,%d,%.3f)".printf(r, g, b, a);
    }

    static void load_from_file () {
        var path = theme_file_path();
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
            var rgba = parse_hex_to_rgba(node.get_string());
            if (rgba == null) return;
            palette.insert(key_to_var(name), rgba);
        });
    }

    static string build_define_color_block () {
        var sb = new StringBuilder();
        palette.foreach((k, v) => {
            sb.append_printf("@define-color %s %s;\n", k, v);
        });
        return sb.str;
    }

    // Loads the embedded base CSS, prepends @define-color overrides from JSON,
    // and installs a CssProvider on the default display.
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
