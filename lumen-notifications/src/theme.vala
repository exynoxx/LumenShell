using Json;

public enum DismissStyle {
    SLIDE_RIGHT,
    FADE;

    public static DismissStyle? parse(string s) {
        switch (s) {
            case "slide-right": return SLIDE_RIGHT;
            case "fade":        return FADE;
            default:            return null;
        }
    }
}

public class Theme {
    public static Gdk.RGBA banner_bg       = rgba(0.07f, 0.08f, 0.12f, 0.96f);
    public static Gdk.RGBA banner_border   = rgba(1.00f, 1.00f, 1.00f, 0.12f);
    public static Gdk.RGBA banner_text     = rgba(0.92f, 0.92f, 0.92f, 1.00f);
    public static Gdk.RGBA banner_subtext  = rgba(0.69f, 0.69f, 0.69f, 1.00f);
    public static Gdk.RGBA action_bg       = rgba(1.00f, 1.00f, 1.00f, 0.08f);
    public static Gdk.RGBA action_bg_hover = rgba(1.00f, 1.00f, 1.00f, 0.16f);
    public static Gdk.RGBA action_text     = rgba(1.00f, 1.00f, 1.00f, 1.00f);
    public static int     action_radius    = 8;
    public static int     clear_all_radius = 6;

    public static Gdk.RGBA urgency_low      = rgba(0.36f, 0.55f, 0.94f, 1.00f);
    public static Gdk.RGBA urgency_normal   = rgba(0.98f, 0.66f, 0.20f, 1.00f);
    public static Gdk.RGBA urgency_critical = rgba(0.88f, 0.35f, 0.30f, 1.00f);

    public static int radius        = 12;
    public static int padding       = 14;
    public static int spacing       = 8;
    public static int width         = 360;
    public static int gap           = 10;
    public static int margin_top    = 16;
    public static int margin_right  = 16;

    public static int fade_out_ms   = 800;
    public static int slide_px      = 24;

    public static int expire_default_ms = 5000;

    // Dismiss animation: slide-right or fade.
    public static DismissStyle dismiss_style = DismissStyle.SLIDE_RIGHT;
    public static int          cascade_ms       = 80;
    public static int          clear_threshold  = 3;

    public static void load() {
        var path = Utils.THEME_FILE;
        if (!FileUtils.test(path, FileTest.EXISTS)) return;

        var parser = new Json.Parser();
        try {
            parser.load_from_file(path);
        } catch (Error e) {
            stderr.printf("lumen-notifications: theme load failed: %s\n", e.message);
            return;
        }

        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return;

        root.get_object().foreach_member((obj, name, node) => {
            var t = node.get_value_type();
            if (t == typeof(string)) {
                apply_string(name, node.get_string());
            } else if (t == typeof(int64)) {
                apply_int(name, (int) node.get_int());
            }
        });
    }

    private static void apply_string(string key, string val) {
        if (key == "dismiss.style") {
            DismissStyle? d = DismissStyle.parse(val);
            if (d != null) dismiss_style = (!) d;
            else warning("lumen-notifications: unknown dismiss.style: %s", val);
            return;
        }
        if (!val.has_prefix("#")) {
            warning("lumen-notifications: unknown theme key: %s", key);
            return;
        }
        Gdk.RGBA? c = parse_hex(val.substring(1));
        if (c == null) {
            warning("lumen-notifications: invalid color for %s: %s", key, val);
            return;
        }
        switch (key) {
            case "banner.background":        banner_bg        = (!) c; break;
            case "banner.border":            banner_border    = (!) c; break;
            case "banner.text":              banner_text      = (!) c; break;
            case "banner.subtext":           banner_subtext   = (!) c; break;
            case "action.background":        action_bg        = (!) c; break;
            case "action.background-hover":  action_bg_hover  = (!) c; break;
            case "action.text":              action_text      = (!) c; break;
            case "urgency.low.accent":       urgency_low      = (!) c; break;
            case "urgency.normal.accent":    urgency_normal   = (!) c; break;
            case "urgency.critical.accent":  urgency_critical = (!) c; break;
            default:
                warning("lumen-notifications: unknown theme key: %s", key);
                break;
        }
    }

    private static void apply_int(string key, int v) {
        switch (key) {
            case "banner.radius":         radius            = v; break;
            case "banner.padding":        padding           = v; break;
            case "banner.spacing":        spacing           = v; break;
            case "banner.width":          width             = v; break;
            case "banner.gap":            gap               = v; break;
            case "banner.margin.top":     margin_top        = v; break;
            case "banner.margin.right":   margin_right      = v; break;
            case "action.radius":         action_radius     = v; break;
            case "clear-all.radius":      clear_all_radius  = v; break;
            case "animation.fade-out-ms": fade_out_ms       = v; break;
            case "animation.slide-px":    slide_px          = v; break;
            case "expire.default-ms":     expire_default_ms = v; break;
            case "dismiss.cascade-ms":    cascade_ms        = v; break;
            case "clear-all.threshold":   clear_threshold   = v; break;
            default:
                warning("lumen-notifications: unknown theme key: %s", key);
                break;
        }
    }

    public static string generate_root_css() {
        return ".lumen-notif-root { background-color: transparent; }" +
               ".lumen-notif-title { font-weight: bold; color: %s; }".printf(banner_text.to_string()) +
               ".lumen-notif-body  { color: %s; }".printf(banner_subtext.to_string()) +
               generate_action_css() +
               generate_clear_all_css();
    }

    public static string generate_clear_all_css() {
        return ("""
        .lumen-notif-clear-all,
        .lumen-notif-clear-all:focus {
            background-color: %s;
            background-image: none;
            color: %s;
            border: 1px solid %s;
            border-radius: %dpx;
            padding: 8px 16px;
            min-height: 0;
            box-shadow: none;
            outline: none;
            text-shadow: none;
            font-weight: 600;
        }
        .lumen-notif-clear-all:hover  { background-color: %s; }
        .lumen-notif-clear-all:active { background-color: %s; }
        """).printf(
            Theme.banner_bg.to_string(),
            Theme.banner_text.to_string(),
            Theme.banner_border.to_string(),
            Theme.clear_all_radius,
            Theme.action_bg_hover.to_string(),
            Theme.action_bg.to_string()
        );
    }

    public static string generate_action_css() {
        // GNOME-shell-style flat action buttons:
        //   - transparent base, subtle hover
        //   - no per-button radius (parent's rounded clip handles the bottom
        //     corners; intermediate edges stay flat)
        //   - 1px separator between the body and the action row, and between
        //     adjacent buttons
        string sep = Theme.banner_border.to_string();
        return ("""
        .lumen-notif-actions {
            border-top: 1px solid %s;
        }
        .lumen-notif-action,
        .lumen-notif-action:focus {
            background-color: transparent;
            background-image: none;
            color: %s;
            border: none;
            border-radius: 0;
            padding: 10px 12px;
            min-height: 0;
            box-shadow: none;
            outline: none;
            text-shadow: none;
        }
        .lumen-notif-action:hover {
            background-color: %s;
        }
        .lumen-notif-action:active {
            background-color: %s;
        }
        .lumen-notif-action:not(:first-child) {
            border-left: 1px solid %s;
        }
        """).printf(
            sep,
            Theme.action_text.to_string(),
            Theme.action_bg_hover.to_string(),
            Theme.action_bg.to_string(),
            sep
        );
    }

    private static Gdk.RGBA rgba(float r, float g, float b, float a) {
        var c = Gdk.RGBA();
        c.red = r; c.green = g; c.blue = b; c.alpha = a;
        return c;
    }

    private static Gdk.RGBA? parse_hex(string hex) {
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
        return rgba(r, g, b, a);
    }
}
