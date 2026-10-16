public class Utils {
    public static string THEME_FILE {
        owned get {
            return LumenCommon.Paths.theme_file(
                "LUMEN_LOCKSCREEN_THEME_FILE", "lockscreen.json",
                null);
        }
    }

    // PAM service name — must match data/pam.d/lumen-lockscreen.
    public const string PAM_SERVICE = "lumen-lockscreen";
}
