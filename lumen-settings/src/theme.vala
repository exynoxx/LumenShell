using LumenCommon;
using Json;

namespace LumenSettings {

    public class Theme : GLib.Object {
        static GLib.HashTable<string, string> palette;

        public static string THEME_FILE {
            owned get {
                return LumenCommon.Paths.theme_file(
                    "LUMEN_SETTINGS_THEME_FILE", "theme.json",
                    "lumen-settings/default-settings-theme.json");
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

        // Only the colors style.css references; extra theme.json keys still get emitted.
        static void seed_defaults() {
            palette = new GLib.HashTable<string, string>(str_hash, str_equal);
            palette.insert("settings_window_background", "rgba(26,29,39,1)");
            palette.insert("settings_text",              "rgba(234,236,242,1)");
            palette.insert("settings_subtitle",          "rgba(154,160,181,1)");
        }

        static string key_to_var(string json_key) {
            return json_key.replace(".", "_").replace("-", "_");
        }
    }
}
