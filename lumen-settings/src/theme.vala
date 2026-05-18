using Json;

namespace LumenSettings {

    public class Theme : GLib.Object {
        static GLib.HashTable<string, string> palette;

        public static string THEME_FILE {
            owned get {
                var env = Environment.get_variable("LUMEN_SETTINGS_THEME_FILE");
                if (env != null) return env;
                var home = Paths.config_dir() + "/theme.json";
                if (FileUtils.test(home, FileTest.EXISTS)) return home;
                return "/usr/share/lumen-settings/default-settings-theme.json";
            }
        }

        public static void load() {
            seed_defaults();
            var path = THEME_FILE;
            if (!FileUtils.test(path, FileTest.EXISTS)) return;

            var parser = new Json.Parser();
            try {
                parser.load_from_file(path);
            } catch (Error e) {
                stderr.printf("lumen-settings theme load failed: %s\n", e.message);
                return;
            }
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return;
            root.get_object().foreach_member((obj, name, node) => {
                if (node.get_value_type() != typeof(string)) return;
                var rgba = Gdk.RGBA();
                if (!rgba.parse(node.get_string())) return;
                palette.insert(key_to_var(name), rgba.to_string());
            });
        }

        public static string generate_root_css() {
            var sb = new StringBuilder();
            palette.foreach((k, v) => {
                sb.append_printf("@define-color %s %s;\n", k, v);
            });
            return sb.str;
        }

        static void seed_defaults() {
            palette = new GLib.HashTable<string, string>(str_hash, str_equal);
            palette.insert("settings_window_background",   "rgba(26,29,39,1)");
            palette.insert("settings_sidebar_background",  "rgba(20,23,32,1)");
            palette.insert("settings_row_background",      "rgba(34,38,51,1)");
            palette.insert("settings_row_hover",           "rgba(44,49,64,1)");
            palette.insert("settings_row_active",          "rgba(54,59,77,1)");
            palette.insert("settings_text",                "rgba(234,236,242,1)");
            palette.insert("settings_subtitle",            "rgba(154,160,181,1)");
            palette.insert("settings_accent",              "rgba(61,122,255,1)");
            palette.insert("settings_border",              "rgba(0,0,0,0.27)");
        }

        static string key_to_var(string json_key) {
            return json_key.replace(".", "_").replace("-", "_");
        }
    }
}
