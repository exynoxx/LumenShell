using Gtk;

namespace LumenSettings {

    public class OsdPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "osd"; } }
        public string title     { owned get { return "OSD"; } }
        public string icon_name { owned get { return "preferences-desktop-symbolic"; } }

        JsonStore store;

        public Gtk.Widget build() {
            store = new JsonStore(Paths.osd_json());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var placement = new BoxedList("Placement");
            string[] pos_labels = {
                "Top left", "Top center", "Top right",
                "Center",
                "Bottom left", "Bottom center", "Bottom right",
            };
            string[] pos_values = {
                "top-left", "top-center", "top-right",
                "center",
                "bottom-left", "bottom-center", "bottom-right",
            };
            var pos_initial = store.get_string("osd.position") ?? "bottom-center";
            var pos_row = new ComboRow("Position", pos_labels, pos_values, pos_initial, "where OSD popups appear on the screen");
            pos_row.value_changed.connect((v) => {
                store.set_string("osd.position", v);
                store.save();
            });
            placement.add_row(pos_row);
            placement.add_row(int_row("osd.margin", "Margin from edge", 0, 400, 1, 76, "px from the screen's anchored edge"));
            box.append(placement);

            var size = new BoxedList("Size");
            size.add_row(int_row("osd.width",  "Width",  100, 800, 1, 360, "OSD popup width in px"));
            size.add_row(int_row("osd.height", "Height", 24,  200, 1, 56,  "OSD popup height in px"));
            box.append(size);

            var behavior = new BoxedList("Behavior");
            behavior.add_row(int_row("osd.timeout-ms", "Timeout", 200, 10000, 100, 1500, "milliseconds before auto-dismiss"));
            box.append(behavior);

            var spacing = new BoxedList("Spacing");
            spacing.add_row(int_row("osd.padding-x",       "Horizontal padding", 0, 100, 1, 22, "px of inner padding on the left and right"));
            spacing.add_row(int_row("osd.padding-y",       "Vertical padding",   0, 100, 1, 10, "px of inner padding on the top and bottom"));
            spacing.add_row(int_row("osd.content-spacing", "Content gap",        0, 60,  1, 14, "px between the icon, label, and progress bar"));
            box.append(spacing);

            return box;
        }

        SpinRow int_row(string key, string label, double min, double max,
                        double step, int64 fallback, string subtitle = "") {
            var initial = (double) store.get_int(key, fallback);
            var row = new SpinRow(label, min, max, step, initial, 0, subtitle);
            row.value_changed.connect((v) => {
                store.set_int(key, (int64) v);
                store.save();
            });
            return row;
        }
    }
}
