// Resolved metadata for one app_id. `info` is null when no .desktop file could
// be found; `name` then falls back to the app_id itself.
public struct AppMetadata {
    public string name;
    public DesktopAppInfo? info;
}

public class Utils {

    public static string THEME_FILE {
        owned get {
            return LumenCommon.Paths.theme_file(
                "LUMEN_THEME_FILE", "theme.json",
                "lumen-panel/default-theme.json");
        }
    }

    // Case-insensitive prefix match over the registered applications, for
    // app_ids whose case doesn't match the .desktop filename.
    static DesktopAppInfo? find_by_prefix (string app_id) {
        string needle = app_id.down();
        foreach (unowned AppInfo app in AppInfo.get_all()) {
            var desktop = app as DesktopAppInfo;
            if (desktop == null) continue;
            unowned string? id = desktop.get_id();
            if (id != null && id.down().has_prefix(needle)) return desktop;
        }
        return null;
    }

    // Resolve app metadata via GLib.DesktopAppInfo (which does the XDG search),
    // falling back to the fuzzy prefix match.
    public static AppMetadata load_app_metadata (string app_id) {
        AppMetadata m = { app_id, null };

        DesktopAppInfo? info = new DesktopAppInfo(app_id + ".desktop");
        if (info == null) info = find_by_prefix(app_id);
        if (info == null) return m;

        m.info = info;
        string? name = info.get_name();
        if (name != null && name != "") m.name = name;
        return m;
    }
}
