using GLib;

// Resolved metadata for one app_id. Empty strings mean "not found" — keeps
// the type total so callers don't sprinkle null checks.
public struct AppMetadata {
    public string name;
    public string icon;
    public string launch_cmd;
}

public class Utils {

    public static string RES_DIR {
        get { return Environment.get_variable("LUMEN_RES_DIR") ?? "/usr/share/lumen-panel/res/"; }
    }

    // Precedence: explicit env override → the user's config in
    // ~/.config/lumen-shell/ (what lumen-settings writes) → the packaged
    // read-only default. This keeps all editable config in the home dir.
    public static string THEME_FILE {
        owned get {
            var env = Environment.get_variable("LUMEN_THEME_FILE");
            if (env != null) return env;
            var home = Environment.get_user_config_dir() + "/lumen-shell/theme.json";
            if (FileUtils.test(home, FileTest.EXISTS)) return home;
            return "/usr/share/lumen-panel/default-theme.json";
        }
    }

    public static Gdk.RGBA rgba (float r, float g, float b, float a) {
        var c = Gdk.RGBA();
        c.red = r; c.green = g; c.blue = b; c.alpha = a;
        return c;
    }

    static string[] xdg_app_dirs () {
        var dirs = new Gee.ArrayList<string>();
        dirs.add(Environment.get_user_data_dir());
        foreach (unowned string d in Environment.get_system_data_dirs()) dirs.add(d);
        return dirs.to_array();
    }

    // Case-insensitive prefix scan as a fallback for app_ids whose case
    // doesn't match the .desktop filename. Returns a full path or null.
    static string? find_desktop_file (string app_id) {
        string needle = app_id.down();
        foreach (string data_dir in xdg_app_dirs()) {
            string apps_dir = Path.build_filename(data_dir, "applications");
            try {
                var dir = Dir.open(apps_dir);
                string? name;
                while ((name = dir.read_name()) != null) {
                    if (name.has_suffix(".desktop") && name.down().has_prefix(needle))
                        return Path.build_filename(apps_dir, name);
                }
            } catch (FileError e) {}
        }
        return null;
    }

    // Pull Name/Icon/Exec out of a resolved DesktopAppInfo into the struct.
    // Icon stays the raw "Icon" name string (the panel stores a name, not a
    // GIcon); Exec is field-code-stripped via sanitize_exec.
    static void fill_from_info (DesktopAppInfo info, ref AppMetadata m) {
        string? nm = info.get_name();
        if (nm != null) m.name = nm;
        string? ic = info.get_string("Icon");
        if (ic != null) m.icon = ic;
        m.launch_cmd = sanitize_exec(info.get_string("Exec") ?? "");
    }

    // Resolve app metadata via GLib.DesktopAppInfo (which does the XDG search).
    // Falls back to a case-insensitive prefix scan when the exact <app_id>.desktop
    // file doesn't exist.
    public static AppMetadata load_app_metadata (string app_id) {
        AppMetadata m = { app_id, "", "" };

        var info = new DesktopAppInfo(app_id + ".desktop");
        if (info != null) {
            fill_from_info(info, ref m);
            return m;
        }

        // Fuzzy fallback: prefix-match a .desktop filename, then load it by path.
        string? path = find_desktop_file(app_id);
        if (path == null) return m;

        var finfo = new DesktopAppInfo.from_filename(path);
        if (finfo == null) return m;

        fill_from_info(finfo, ref m);
        return m;
    }

    // Strip the freedesktop field codes (%U %u %F %f %i %c %k) that the panel
    // can't fill in.
    static string sanitize_exec (string exec) {
        var sb = new StringBuilder();
        foreach (var token in exec.split(" ")) {
            if (token == "" || token.has_prefix("%")) continue;
            var cleaned = token
                .replace("%U", "").replace("%u", "")
                .replace("%F", "").replace("%f", "")
                .replace("%i", "").replace("%c", "").replace("%k", "");
            if (cleaned.strip() == "") continue;
            if (sb.len > 0) sb.append_c(' ');
            sb.append(cleaned);
        }
        return sb.str;
    }
}
