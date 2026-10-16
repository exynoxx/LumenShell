public class Theme {
    // Theme is never instantiated, so non-const static initializers (emitted
    // into class_init) would never run; load() assigns every field instead.
    public static Gdk.RGBA background;
    public static Gdk.RGBA text;
    public static Gdk.RGBA progress_track;
    public static Gdk.RGBA progress_fill;

    public static string  position;
    public static int     margin;           // px from anchored edge
    public static int     width;
    public static int     height;
    public static int     corner_radius;    // -1 → pill (height/2)
    public static int     timeout_ms;
    public static int     padding_x;        // pill internal horizontal padding
    public static int     padding_y;        // pill internal vertical padding
    public static int     content_spacing;  // gap between icon / bar / label

    // Side anchors (…-left / …-right) stack the pill vertically; the top/bottom
    // centred anchors and dead centre stay horizontal.
    public static bool vertical() {
        return position.has_suffix("-left") || position.has_suffix("-right");
    }

    public static void load() {
        var t = new LumenCommon.ThemeJson(Utils.THEME_FILE);
        position        = t.get_str("osd.position", "bottom-center");
        background      = t.get_color("osd.background", "rgba(0,0,0,0.75)");
        text            = t.get_color("osd.text", "rgba(255,255,255,1)");
        progress_track  = t.get_color("osd.progress.track", "rgba(255,255,255,0.15)");
        progress_fill   = t.get_color("osd.progress.fill", "rgba(255,255,255,1)");
        margin          = t.get_int("osd.margin", 76);
        width           = t.get_int("osd.width", 360);
        height          = t.get_int("osd.height", 56);
        corner_radius   = t.get_int("osd.corner-radius", -1);
        timeout_ms      = t.get_int("osd.timeout-ms", 1500);
        padding_x       = t.get_int("osd.padding-x", 22);
        padding_y       = t.get_int("osd.padding-y", 10);
        content_spacing = t.get_int("osd.content-spacing", 14);
    }

    public static string generate_root_css() {
        return (".lumen-osd-root { background-color: transparent; }" +
                ".lumen-osd-root label { color: %s; }" +
                ".lumen-osd-root image { color: %s; }").printf(
                    text.to_string(), text.to_string());
    }
}
