namespace LumenSettings {

    public class Theme : GLib.Object {
        public static string THEME_FILE {
            owned get {
                return LumenCommon.Paths.theme_file(
                    "LUMEN_SETTINGS_THEME_FILE", "theme.json",
                    "lumen-settings/default-settings-theme.json");
            }
        }

        // Defaults are only the colors style.css references; extra theme.json keys still get emitted.
        public static void install() {
            var palette = new LumenCommon.Palette(THEME_FILE, {
                "settings_window_background", "rgba(26,29,39,1)",
                "settings_text",              "rgba(234,236,242,1)",
                "settings_subtitle",          "rgba(154,160,181,1)",
            });
            LumenCommon.Css.install_resource("/org/lumenshell/settings/res/style.css", palette.define_colors());
        }
    }
}
