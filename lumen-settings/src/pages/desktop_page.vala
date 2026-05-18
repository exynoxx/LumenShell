using Gtk;

namespace LumenSettings {

    public class DesktopPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "desktop"; } }
        public string title     { owned get { return "Desktop"; } }
        public string icon_name { owned get { return "view-grid-symbolic"; } }

        IniStore store;
        const string SECTION = "desktop";

        public Gtk.Widget build() {
            store = new IniStore(Paths.desktop_ini());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var group = new BoxedList("App grid");
            group.add_row(int_row("grid.cols",   "Columns", 1, 12, 6, "number of app icons per row"));
            group.add_row(int_row("grid.rows",   "Rows",    1, 8,  4, "number of app icon rows per page"));
            group.add_row(int_row("grid.margin", "Page margin", 0, 200, 40, "px of empty space around the grid"));
            box.append(group);

            return box;
        }

        SpinRow int_row(string key, string label, double min, double max,
                        double fallback, string subtitle = "") {
            var initial = parse_double(store.get_value(SECTION, key), fallback);
            var row = new SpinRow(label, min, max, 1, initial, 0, subtitle);
            row.value_changed.connect((v) => {
                store.set_value(SECTION, key, "%d".printf((int) v));
                store.save();
            });
            return row;
        }

        static double parse_double(string? s, double fallback) {
            if (s == null) return fallback;
            double d;
            return double.try_parse(s, out d) ? d : fallback;
        }
    }
}
