using Json;

// Theme — static config for lumen-lockscreen, mirroring lumen-osd/src/theme.vala.
// Exposes typed fields for code (colors as Gdk.RGBA, sizes as int, flags as
// bool) AND a generate_root_css() that emits @define-color tokens so the stock
// GTK widgets on the card (Gtk.PasswordEntry, buttons) pick up the palette.
public class Theme {
    // See lumen-osd note: Theme is never instantiated, so non-const field
    // initializers never run; load() sets every field imperatively.
    public static Gdk.RGBA background;        // page fill behind everything
    public static Gdk.RGBA text;              // primary text (clock, name)
    public static Gdk.RGBA muted_text;        // date, hints
    public static Gdk.RGBA entry_background;
    public static Gdk.RGBA entry_border;
    public static Gdk.RGBA entry_error;
    public static Gdk.RGBA accent;
    public static Gdk.RGBA scrim;             // tint over the blurred desktop snapshot

    public static string background_image;    // fallback when no snapshot ("" = solid)
    public static int    clock_font_size   = 96;
    public static int    date_font_size    = 18;
    public static int    avatar_size       = 256;
    public static int    corner_radius     = 16;
    public static int    blur_radius       = 12;       // light GSK frost over the wallpaper
    public static int    idle_timeout_ms   = 300000;   // ext-idle-notify-v1; 0 disables auto-lock
    public static int    failure_backoff_ms = 3000;
    public static bool   show_power_menu   = true;

    // Pre-lock transition (see LockEffect). effect: "none" | "converge" | "flip".
    // flip_axis: "y" (rotate about the vertical axis) | "x" (horizontal axis).
    public static string effect             = "converge";
    public static string flip_axis          = "y";
    public static int    effect_duration_ms = 300;

    public static void load() {
        background       = rgba(0.06f, 0.07f, 0.09f, 1.00f);
        text             = rgba(1.00f, 1.00f, 1.00f, 1.00f);
        muted_text       = rgba(0.90f, 0.90f, 0.94f, 0.75f);
        // Apple-style translucent-white password pill on a blurred backdrop.
        entry_background = rgba(1.00f, 1.00f, 1.00f, 0.18f);
        entry_border     = rgba(1.00f, 1.00f, 1.00f, 0.28f);
        entry_error      = rgba(0.95f, 0.42f, 0.42f, 1.00f);
        accent           = rgba(1.00f, 1.00f, 1.00f, 0.92f);
        scrim            = rgba(0.00f, 0.00f, 0.00f, 0.35f);
        background_image = "";
        effect             = "converge";
        flip_axis          = "y";
        effect_duration_ms = 300;

        var path = Utils.THEME_FILE;
        if (!FileUtils.test(path, FileTest.EXISTS)) return;

        var parser = new Json.Parser();
        try {
            parser.load_from_file(path);
        } catch (Error e) {
            stderr.printf("lumen-lockscreen theme load failed: %s\n", e.message);
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
            } else if (t == typeof(bool)) {
                apply_bool(name, node.get_boolean());
            }
        });
    }

    private static void apply_string(string key, string val) {
        if (key == "lockscreen.background-image") {
            background_image = val;
            return;
        }
        if (key == "lockscreen.effect") {
            effect = val;
            return;
        }
        if (key == "lockscreen.flip-axis") {
            flip_axis = val;
            return;
        }
        if (!val.has_prefix("#")) {
            warning("lumen-lockscreen: unknown theme key: %s", key);
            return;
        }
        Gdk.RGBA? c = parse_hex(val.substring(1));
        if (c == null) {
            warning("lumen-lockscreen: invalid color for %s: %s", key, val);
            return;
        }
        switch (key) {
            case "lockscreen.background":       background       = (!) c; break;
            case "lockscreen.text":             text             = (!) c; break;
            case "lockscreen.muted-text":       muted_text       = (!) c; break;
            case "lockscreen.entry-background": entry_background = (!) c; break;
            case "lockscreen.entry-border":     entry_border     = (!) c; break;
            case "lockscreen.entry-error":      entry_error      = (!) c; break;
            case "lockscreen.accent":           accent           = (!) c; break;
            case "lockscreen.scrim":            scrim            = (!) c; break;
            default:
                warning("lumen-lockscreen: unknown theme key: %s", key);
                break;
        }
    }

    private static void apply_int(string key, int v) {
        switch (key) {
            case "lockscreen.clock-font-size":    clock_font_size    = v; break;
            case "lockscreen.date-font-size":     date_font_size     = v; break;
            case "lockscreen.avatar-size":        avatar_size        = v; break;
            case "lockscreen.corner-radius":      corner_radius      = v; break;
            case "lockscreen.blur-radius":        blur_radius        = v; break;
            case "lockscreen.idle-timeout-ms":    idle_timeout_ms    = v; break;
            case "lockscreen.failure-backoff-ms": failure_backoff_ms = v; break;
            case "lockscreen.effect-duration-ms": effect_duration_ms = v; break;
            default:
                warning("lumen-lockscreen: unknown theme key: %s", key);
                break;
        }
    }

    private static void apply_bool(string key, bool v) {
        switch (key) {
            case "lockscreen.show-power-menu": show_power_menu = v; break;
            default:
                warning("lumen-lockscreen: unknown theme key: %s", key);
                break;
        }
    }

    // @define-color tokens consumed by res/style.css for the stock widgets.
    public static string generate_root_css() {
        return ("@define-color lockscreen_text %s;\n"             +
                "@define-color lockscreen_muted_text %s;\n"       +
                "@define-color lockscreen_accent %s;\n"           +
                "@define-color lockscreen_entry_background %s;\n" +
                "@define-color lockscreen_entry_border %s;\n"     +
                "@define-color lockscreen_entry_error %s;\n").printf(
                    text.to_string(), muted_text.to_string(), accent.to_string(),
                    entry_background.to_string(), entry_border.to_string(),
                    entry_error.to_string());
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
