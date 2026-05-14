using GLib;

public class Utils {
    public static string THEME_FILE {
        get {
            return Environment.get_variable("LUMEN_NOTIFICATIONS_THEME_FILE")
                   ?? "/usr/share/lumen-notifications/default-notifications-theme.json";
        }
    }
}
