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
            panel_group.add_row(color_row("panel.background",      "Panel background",      "#1a1d27ff"));
            panel_group.add_row(color_row("tray.background",       "Tray background",       "#222633ff"));
            panel_group.add_row(color_row("tray.icon-hover",       "Tray icon hover",       "#2c3140ff"));
            panel_group.add_row(color_row("app.hover",             "App hover",             "#2c3140ff"));
            panel_group.add_row(color_row("app.launching",         "App launching",         "#3d7affff"));
            panel_group.add_row(color_row("app.active-underline",  "Active app underline",  "#3d7affff"));
            box.append(panel_group);

            var osd_group = new BoxedList("OSD");
            osd_group.add_row(color_row("osd.background",      "OSD background",     "#000000bf"));
            osd_group.add_row(color_row("osd.text",            "OSD text",           "#ffffffff"));
            osd_group.add_row(color_row("osd.progress.track",  "Progress track",     "#ffffff26"));
            osd_group.add_row(color_row("osd.progress.fill",   "Progress fill",      "#ffffffff"));
            box.append(osd_group);

            return box;
        }

        ColorRow color_row(string key, string label, string fallback) {
            var initial = store.get_string(key) ?? fallback;
            var row = new ColorRow(label, initial);
            row.value_changed.connect((hex) => {
                store.set_string(key, hex);
                store.save();
            });
            return row;
        }
    }
}
