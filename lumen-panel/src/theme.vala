public class Theme : GLib.Object {

    // Set by install(); never-instantiated class, so no static initializer.
    static LumenCommon.Palette? palette;

    // For code paths that draw with Gdk.RGBA, where CSS @-references don't apply.
    public static Gdk.RGBA color (string json_key, string fallback) {
        if (palette == null) {
            var c = Gdk.RGBA();
            c.parse(fallback);
            return c;
        }
        return palette.color(json_key, fallback);
    }

    public static void install () {
        // Defaults mirror default-theme.json. The auto-hide backdrop shares the
        // panel's RGB by default but has its own alpha (settings syncs the RGB).
        palette = new LumenCommon.Palette(Utils.THEME_FILE, {
            "panel_background",          "rgba(0,0,0,0)",
            "tray_background",           "rgba(17,20,31,0.97)",
            "tray_icon_hover",           "rgba(41,46,66,1)",
            "app_hover",                 "rgba(255,255,255,0.20)",
            "app_active_underline",      "rgba(0,44,230,1)",
            "panel_autohide_background", "rgba(17,20,31,0.5)",
        });
        LumenCommon.Css.install_resource("/dev/lumen/panel/style.css", palette.define_colors());
    }
}
