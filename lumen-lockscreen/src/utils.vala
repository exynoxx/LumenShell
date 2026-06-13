using GLib;

public class Utils {
    // Precedence mirrors lumen-osd: explicit env override → user config in
    // ~/.config/lumen-shell/ → packaged read-only default.
    public static string THEME_FILE {
        owned get {
            var env = Environment.get_variable("LUMEN_LOCKSCREEN_THEME_FILE");
            if (env != null) return env;
            var home = Environment.get_user_config_dir() + "/lumen-shell/lockscreen.json";
            if (FileUtils.test(home, FileTest.EXISTS)) return home;
            return "/usr/share/lumen-lockscreen/default-lockscreen-theme.json";
        }
    }

    // PAM service name — must match data/pam.d/lumen-lockscreen.
    public const string PAM_SERVICE = "lumen-lockscreen";
}
