using GLib;

public class Utils {
    public static string THEME_FILE {
        owned get {
            return LumenCommon.Paths.theme_file(
                "LUMEN_OSD_THEME_FILE", "osd.json",
                null);
        }
    }
}
