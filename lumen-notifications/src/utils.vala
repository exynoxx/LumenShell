using GLib;

public class Utils {
    // Precedence: explicit env override → the user's config in
    // ~/.config/lumen-shell/ (what lumen-settings writes) → the packaged
    // read-only default. This keeps all editable config in the home dir.
    public static string THEME_FILE {
        owned get {
            var env = Environment.get_variable("LUMEN_NOTIFICATIONS_THEME_FILE");
            if (env != null) return env;
            var home = Environment.get_user_config_dir() + "/lumen-shell/notifications.json";
            if (FileUtils.test(home, FileTest.EXISTS)) return home;
            return "/usr/share/lumen-notifications/default-notifications-theme.json";
        }
    }
}
