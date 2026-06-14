using GLib;

// Install datadir baked in at build time (meson -DLUMEN_DATADIR=...), so the
// packaged default theme is found whatever the prefix (/usr vs /usr/local).
[CCode (cname = "LUMEN_DATADIR")]
extern const string LUMEN_DATADIR;

public class Utils {
    // Precedence mirrors lumen-osd: explicit env override → user config in
    // ~/.config/lumen-shell/ → packaged read-only default (in the build-time
    // datadir, with a hardcoded /usr/share fallback for safety).
    public static string THEME_FILE {
        owned get {
            var env = Environment.get_variable("LUMEN_LOCKSCREEN_THEME_FILE");
            if (env != null) return env;
            var home = Environment.get_user_config_dir() + "/lumen-shell/lockscreen.json";
            if (FileUtils.test(home, FileTest.EXISTS)) return home;
            var packaged = LUMEN_DATADIR + "/lumen-lockscreen/default-lockscreen-theme.json";
            if (FileUtils.test(packaged, FileTest.EXISTS)) return packaged;
            return "/usr/share/lumen-lockscreen/default-lockscreen-theme.json";
        }
    }

    // PAM service name — must match data/pam.d/lumen-lockscreen.
    public const string PAM_SERVICE = "lumen-lockscreen";
}
