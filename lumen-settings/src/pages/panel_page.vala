using Gtk;

namespace LumenSettings {

    public class PanelPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "panel"; } }
        public string title     { owned get { return "Panel"; } }
        public string icon_name { owned get { return "preferences-system-symbolic"; } }

        IniStore store;
        const string SECTION = "panel";

        public Gtk.Widget build() {
            store = new IniStore(Paths.panel_ini());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var layout = new BoxedList("Layout");
            var height_initial = parse_double(store.get_value(SECTION, "panel.height"), 60);
            var height_row = new SpinRow("Panel height", 40, 120, 1, height_initial, 0, "px");
            height_row.value_changed.connect((v) => {
                store.set_value(SECTION, "panel.height", "%d".printf((int) v));
                store.save();
            });
            layout.add_row(height_row);
            box.append(layout);

            var clock_group = new BoxedList("Clock");

            var fmt_initial = store.get_value(SECTION, "clock.format") ?? "%H:%M";
            var fmt_row = new EntryRow("Format", fmt_initial, "strftime pattern");
            fmt_row.value_changed.connect((v) => {
                store.set_value(SECTION, "clock.format", v);
                store.save();
            });
            clock_group.add_row(fmt_row);

            string[] click_labels = { "Do nothing", "Open calendar", "Run command" };
            string[] click_values = { "none", "open-calendar", "run-command" };
            var click_initial = store.get_value(SECTION, "clock.on-click") ?? "none";
            var click_row = new ComboRow("On click", click_labels, click_values, click_initial);
            click_row.value_changed.connect((v) => {
                store.set_value(SECTION, "clock.on-click", v);
                store.save();
            });
            clock_group.add_row(click_row);

            var cmd_initial = store.get_value(SECTION, "clock.command") ?? "";
            var cmd_row = new EntryRow("Command", cmd_initial, "used when on-click = run-command");
            cmd_row.value_changed.connect((v) => {
                store.set_value(SECTION, "clock.command", v);
                store.save();
            });
            clock_group.add_row(cmd_row);

            box.append(clock_group);
            return box;
        }

        static double parse_double(string? s, double fallback) {
            if (s == null) return fallback;
            double d;
            return double.try_parse(s, out d) ? d : fallback;
        }
    }
}
