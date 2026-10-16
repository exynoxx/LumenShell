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
        public static string desktop_json()          { return config_dir() + "/desktop.json"; }
        public static string osd_json()              { return config_dir() + "/osd.json"; }
        public static string notifications_json()    { return config_dir() + "/notifications.json"; }
        public static string wallpaper_ini()         { return config_dir() + "/wallpaper.ini"; }
        public static string lockscreen_json()       { return config_dir() + "/lockscreen.json"; }
        public static string power_ini()             { return config_dir() + "/power.ini"; }
        public static string display_profiles_json() { return config_dir() + "/display-profiles.json"; }
        public static string radio_state_json()      { return config_dir() + "/radio-state.json"; }

        // Wayfire's own config lives beside ours, not inside lumen-shell/.
        public static string wayfire_ini() {
            return Environment.get_user_config_dir() + "/wayfire.ini";
        }

        // wf-background's config, also beside ours rather than inside.
        public static string wf_shell_ini() {
            return Environment.get_user_config_dir() + "/wf-shell.ini";
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

            return "/usr/share/" + packaged_relpath;
        }
    }
}
