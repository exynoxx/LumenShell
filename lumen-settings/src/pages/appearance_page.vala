using Gtk;

namespace LumenSettings {

    public class AppearancePage : GLib.Object, SettingsPage {
        public string id        { owned get { return "appearance"; } }
        public string title     { owned get { return "Appearance"; } }
        public string icon_name { owned get { return "applications-graphics-symbolic"; } }

        JsonStore store;

        public Gtk.Widget build() {
            store = new JsonStore(Paths.theme_json());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var panel_group = new BoxedList("Panel");
            panel_group.add_row(color_row("panel.background",      "Panel background",      "#1a1d27ff", "panel color, including transparency"));
            panel_group.add_row(color_row("tray.background",       "Tray background",       "#222633ff", "tray icon background when not hovered"));
            panel_group.add_row(color_row("tray.icon-hover",       "Tray icon hover",       "#2c3140ff", "tray icon background while the pointer is over it"));
            panel_group.add_row(color_row("app.hover",             "App hover",             "#2c3140ff", "taskbar app background while the pointer is over it"));
            panel_group.add_row(color_row("app.launching",         "App launching",         "#3d7affff", "taskbar app background while the app is starting up"));
            panel_group.add_row(color_row("app.active-underline",  "Active app underline",  "#3d7affff", "underline color shown beneath the focused app"));
            box.append(panel_group);

            var osd_group = new BoxedList("OSD");
            osd_group.add_row(color_row("osd.background",      "OSD background",     "#000000bf", "background of volume and brightness popups"));
            osd_group.add_row(color_row("osd.text",            "OSD text",           "#ffffffff", "label and icon color on OSD popups"));
            osd_group.add_row(color_row("osd.progress.track",  "Progress track",     "#ffffff26", "unfilled portion of the OSD progress bar"));
            osd_group.add_row(color_row("osd.progress.fill",   "Progress fill",      "#ffffffff", "filled portion of the OSD progress bar"));
            box.append(osd_group);

            return box;
        }

        ColorRow color_row(string key, string label, string fallback, string subtitle) {
            var initial = store.get_string(key) ?? fallback;
            var row = new ColorRow(label, initial, subtitle);
            row.value_changed.connect((hex) => {
                store.set_string(key, hex);
                store.save();
            });
            return row;
        }
    }
}
