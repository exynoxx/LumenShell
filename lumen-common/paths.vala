using GLib;

// Baked in by meson (-DLUMEN_DATADIR); the target must pass lumen_datadir_c_args.
[CCode (cname = "LUMEN_DATADIR")]
extern const string LUMEN_DATADIR;

namespace LumenCommon {

    // Every config filename lives here and nowhere else, so a rename can't
    // leave one binary writing a file another no longer reads.
    public class Paths {

        public static string config_dir() {
            return Environment.get_user_config_dir() + "/lumen-shell";
        }

        public static string theme_json()            { return config_dir() + "/theme.json"; }
        public static string panel_json()            { return config_dir() + "/panel.json"; }
        public static string drawer_ini()            { return config_dir() + "/drawer.ini"; }
        public static string osd_json()              { return config_dir() + "/osd.json"; }
        public static string search_json()           { return config_dir() + "/search.json"; }
        public static string notifications_json()    { return config_dir() + "/notifications.json"; }
        public static string wallpaper_ini()         { return config_dir() + "/wallpaper.ini"; }
        public static string lockscreen_json()       { return config_dir() + "/lockscreen.json"; }
        public static string power_ini()             { return config_dir() + "/power.ini"; }
        public static string display_profiles_json() { return config_dir() + "/display-profiles.json"; }

        // Wayfire's own config lives beside ours, not inside lumen-shell/.
        public static string wayfire_ini() {
            return Environment.get_user_config_dir() + "/wayfire.ini";
        }

        // wf-background's config, also beside ours rather than inside.
        public static string wf_shell_ini() {
            return Environment.get_user_config_dir() + "/wf-shell.ini";
        }

        // Regional formats (LC_TIME, ...) for the Users page. environment.d is
        // what reaches the session: GDM imports the systemd user environment,
        // while profile.d (and so Fedora's ~/.i18n) is never sourced. Without
        // systemd (FreeBSD) start-lumenshell sources the same file itself.
        public static string formats_env_conf() {
            return Environment.get_user_config_dir() + "/environment.d/90-lumen-formats.conf";
        }

        public static void ensure_dir() {
            if (DirUtils.create_with_parents(config_dir(), 0755) != 0)
                warning("lumen: could not create %s", config_dir());
        }

        // env override → ~/.config/lumen-shell/<basename> → packaged default.
        // packaged_relpath == null (defaults in code) returns the user path.
        public static string theme_file(string env_var,
                                        string config_basename,
                                        string? packaged_relpath) {
            var env = Environment.get_variable(env_var);
            if (env != null) return env;

            var user = config_dir() + "/" + config_basename;
            if (packaged_relpath == null || FileUtils.test(user, FileTest.EXISTS)) return user;

            var datadir = Environment.get_variable("LUMEN_DATADIR") ?? LUMEN_DATADIR;
            var packaged = datadir + "/" + packaged_relpath;
            if (FileUtils.test(packaged, FileTest.EXISTS)) return packaged;

            return system_data_file(packaged_relpath);
        }

        // First existing <dir>/<relpath> over the XDG system data dirs
        // (GLib defaults them to /usr/local/share:/usr/share, so FreeBSD's
        // ports prefix is found), else the /usr/share path. Used for files
        // other packages install: Wayfire metadata, xkb rules, wallpapers.
        public static string system_data_file(string relpath) {
            foreach (var dir in Environment.get_system_data_dirs()) {
                var p = Path.build_filename(dir, relpath);
                if (FileUtils.test(p, FileTest.EXISTS)) return p;
            }
            return "/usr/share/" + relpath;
        }
    }

    // One-key INI reads. A missing file, group or key, or a parse error, all
    // read as "not set": null / `def`.
    public class Ini {
        public static string? get_str(string path, string group, string key) {
            var kf = new KeyFile();
            try {
                kf.load_from_file(path, KeyFileFlags.NONE);
                return kf.get_string(group, key);
            } catch (Error e) {
                return null;
            }
        }

        public static int get_int(string path, string group, string key, int def) {
            var kf = new KeyFile();
            try {
                kf.load_from_file(path, KeyFileFlags.NONE);
                return kf.get_integer(group, key);
            } catch (Error e) {
                return def;
            }
        }
    }
}
