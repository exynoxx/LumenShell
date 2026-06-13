using Json;

public class Theme {
    // Non-trivial initializers (anything not a C constant expression) are
    // emitted by Vala into class_init. Theme is never instantiated, so
    // class_init never runs and these Gdk.RGBA / string defaults stay
    // zero-initialized — which is fully transparent, hiding the entire OSD.
    // The fields are set imperatively in load() instead; the values below
    // document intent only.
    public static Gdk.RGBA background;       // rgba(0, 0, 0, 0.75)
    public static Gdk.RGBA text;             // rgba(1, 1, 1, 1)
    public static Gdk.RGBA progress_track;   // rgba(1, 1, 1, 0.15)
    public static Gdk.RGBA progress_fill;    // rgba(1, 1, 1, 1)

    public static string  position;          // "bottom-center" (set in load())
    public static int     margin           = 76;       // px from anchored edge
    public static int     width            = 360;
    public static int     height           = 56;
    public static int     corner_radius    = -1;       // -1 → pill (height/2)
    public static int     timeout_ms       = 1500;
    public static int     padding_x        = 22;       // pill internal horizontal padding
    public static int     padding_y        = 10;       // pill internal vertical padding
    public static int     content_spacing  = 14;       // gap between icon / bar / label

    public static void load() {
        position       = "bottom-center";
        background     = rgba(0.00f, 0.00f, 0.00f, 0.75f);
        text           = rgba(1.00f, 1.00f, 1.00f, 1.00f);
        progress_track = rgba(1.00f, 1.00f, 1.00f, 0.15f);
        progress_fill  = rgba(1.00f, 1.00f, 1.00f, 1.00f);

        var path = Utils.THEME_FILE;
        if (!FileUtils.test(path, FileTest.EXISTS)) return;

        var parser = new Json.Parser();
        try {
            parser.load_from_file(path);
        } catch (Error e) {
            stderr.printf("lumen-osd theme load failed: %s\n", e.message);
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
        if (key == "osd.position") {
            position = val;
            return;
        }
        if (!val.has_prefix("#")) {
            warning("lumen-osd: unknown theme key: %s", key);
            return;
        }
        Gdk.RGBA? c = parse_hex(val.substring(1));
        if (c == null) {
            warning("lumen-osd: invalid color for %s: %s", key, val);
            return;
        }
        switch (key) {
            case "osd.background":     background     = (!) c; break;
            case "osd.text":           text           = (!) c; break;
            case "osd.progress.track": progress_track = (!) c; break;
            case "osd.progress.fill":  progress_fill  = (!) c; break;
            default:
                warning("lumen-osd: unknown theme key: %s", key);
                break;
        }
    }

    public static string generate_root_css() {
        return (".lumen-osd-root { background-color: transparent; }" +
                ".lumen-osd-root label { color: %s; }" +
                ".lumen-osd-root image { color: %s; }").printf(
                    text.to_string(), text.to_string());
    }

    private static void apply_int(string key, int v) {
        switch (key) {
            case "osd.margin":          margin          = v; break;
            case "osd.width":           width           = v; break;
            case "osd.height":          height          = v; break;
            case "osd.corner-radius":   corner_radius   = v; break;
            case "osd.timeout-ms":      timeout_ms      = v; break;
            case "osd.padding-x":       padding_x       = v; break;
            case "osd.padding-y":       padding_y       = v; break;
            case "osd.content-spacing": content_spacing = v; break;
            default:
                warning("lumen-osd: unknown theme key: %s", key);
                break;
        }
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
