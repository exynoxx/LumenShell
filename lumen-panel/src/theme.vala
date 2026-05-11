using DrawKit;
using Json;

public class Theme {
    public static Color tray_bg              = Color(){r=0.07f, g=0.08f, b=0.12f, a=0.97f};
    public static Color tray_icon_hover      = Color(){r=0.16f, g=0.18f, b=0.26f, a=1f};
    public static Color app_hover            = Color(){r=1f,    g=1f,    b=1f,    a=0.20f};
    public static Color app_launching        = Color(){r=0.98f, g=0.66f, b=0.20f, a=1f};
    public static Color app_active_underline = Color(){r=0f,    g=0.17f, b=0.9f,  a=1f};

    public static void load() {
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
            var val = node.get_string();
            if (!val.has_prefix("#")) return;
            Color? c = parse_hex(val.substring(1));
            if (c == null) return;
            apply(name, (!) c);
        });
    }

    private static void apply(string key, Color c) {
        switch (key) {
            case "tray.background":      tray_bg = c; break;
            case "tray.icon-hover":      tray_icon_hover = c; break;
            case "app.hover":            app_hover = c; break;
            case "app.launching":        app_launching = c; break;
            case "app.active-underline": app_active_underline = c; break;
        }
    }

    private static Color? parse_hex(string hex) {
        string s = hex;
        if (s.length == 3 || s.length == 4) {
            var sb = new StringBuilder();
            for (int i = 0; i < s.length; i++) {
                sb.append_c(s[i]);
                sb.append_c(s[i]);
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

        float r, g, b, a;
        if (s.length == 6) {
            r = ((v >> 16) & 0xFF) / 255f;
            g = ((v >>  8) & 0xFF) / 255f;
            b = ( v        & 0xFF) / 255f;
            a = 1f;
        } else {
            r = ((v >> 24) & 0xFF) / 255f;
            g = ((v >> 16) & 0xFF) / 255f;
            b = ((v >>  8) & 0xFF) / 255f;
            a = ( v        & 0xFF) / 255f;
        }
        return Color(){r=r, g=g, b=b, a=a};
    }
}
