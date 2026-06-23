// Reads the grid geometry that lumen-settings' Desktop page writes to
// ~/.config/lumen-shell/desktop.ini ([desktop] section: grid.cols, grid.rows,
// grid.margin). Loaded once at startup (main.vala) into the PagedGrid /
// SearchResults globals. A missing file or key leaves the corresponding
// default in place, so an unconfigured session keeps the historical layout.
//
// Minimal hand-rolled INI scan rather than GLib.KeyFile: the keys are dotted
// ("grid.cols"), which KeyFile's key grammar does not officially permit.
namespace LumenDesktop {

    public class DesktopConfig {
        public static int cols   = 6;
        public static int rows   = 4;
        public static int margin = -1;   // -1 = unset; callers keep their own default

        public static void load() {
            var path = Path.build_filename(
                Environment.get_user_config_dir(), "lumen-shell", "desktop.ini");
            if (!FileUtils.test(path, FileTest.EXISTS)) return;

            string content;
            try {
                FileUtils.get_contents(path, out content);
            } catch (Error e) {
                warning("lumen-desktop: reading %s: %s", path, e.message);
                return;
            }

            string section = "";
            foreach (var raw in content.split("\n")) {
                var line = raw.strip();
                if (line == "" || line.has_prefix("#") || line.has_prefix(";")) continue;
                if (line.has_prefix("[") && line.has_suffix("]")) {
                    section = line.substring(1, line.length - 2).strip();
                    continue;
                }
                if (section != "desktop") continue;
                int eq = line.index_of_char('=');
                if (eq < 0) continue;
                var key = line.substring(0, eq).strip();
                var val = line.substring(eq + 1).strip();
                int n;
                if (!int.try_parse(val, out n)) continue;
                switch (key) {
                    case "grid.cols":   if (n > 0)  cols   = n; break;
                    case "grid.rows":   if (n > 0)  rows   = n; break;
                    case "grid.margin": if (n >= 0) margin = n; break;
                }
            }
        }
    }
}
