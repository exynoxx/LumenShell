using GLib;

public class Utils {
    public static string THEME_FILE {
        get {
            return Environment.get_variable("LUMEN_OSD_THEME_FILE")
                   ?? "/usr/share/lumen-osd/default-theme.json";
        }
    }
}
