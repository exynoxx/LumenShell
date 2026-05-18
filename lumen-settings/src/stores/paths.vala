using GLib;

namespace LumenSettings {

    public class Paths {
        public static string config_dir() {
            return Environment.get_user_config_dir() + "/lumen-shell";
        }

        public static string theme_json()         { return config_dir() + "/theme.json"; }
        public static string panel_ini()          { return config_dir() + "/panel.ini"; }
        public static string desktop_ini()        { return config_dir() + "/desktop.ini"; }
        public static string osd_json()           { return config_dir() + "/osd.json"; }
        public static string notifications_json() { return config_dir() + "/notifications.json"; }
        public static string wallpaper_ini()      { return config_dir() + "/wallpaper.ini"; }
        public static string wayfire_ini() {
            return Environment.get_user_config_dir() + "/wayfire.ini";
        }

        public static void ensure_dir() {
            try {
                DirUtils.create_with_parents(config_dir(), 0755);
            } catch (Error e) {
                stderr.printf("lumen-settings: ensure_dir: %s\n", e.message);
            }
        }
    }
}
