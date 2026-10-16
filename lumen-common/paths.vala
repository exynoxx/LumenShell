using GLib;

// Install datadir baked in at build time (meson: -DLUMEN_DATADIR=...), so a
// packaged default is found whatever the prefix (/usr vs /usr/local).
[CCode (cname = "LUMEN_DATADIR")]
extern const string LUMEN_DATADIR;

namespace LumenCommon {

    // Single source of truth for every path LumenShell reads or writes. Each
    // config filename appears exactly once in the tree so a rename can never
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

        public static void ensure_dir() {
            if (DirUtils.create_with_parents(config_dir(), 0755) != 0)
                warning("lumen: could not create %s", config_dir());
        }

        // Resolve a component's theme/config file by the shell-wide precedence:
        // explicit env override → the user's copy in ~/.config/lumen-shell/
        // (what lumen-settings writes) → the packaged read-only default. Keeping
        // all editable config in the home dir is what makes the packaged file
        // safe to overwrite on upgrade.
        //
        // `packaged_relpath` is relative to the datadir, e.g.
        // "lumen-panel/default-theme.json". LUMEN_DATADIR (env, else the value
        // baked in at build time) locates it for non-/usr prefixes. null = no
        // packaged file (defaults live in code): the user path is returned.
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
