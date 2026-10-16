using LumenCommon;
using Gtk;

namespace LumenSettings {

    public class OsdPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "osd"; } }
        public string title     { owned get { return "OSD"; } }
        public string icon_name { owned get { return "preferences-desktop-symbolic"; } }

        JsonRows rows;

        public Gtk.Widget build() {
            rows = new JsonRows(new JsonStore(Paths.osd_json()));

            var page = new Adw.PreferencesPage();

            var placement = new Adw.PreferencesGroup() { title = "Placement" };
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
            placement.add(rows.combo_row("osd.position", "Position", pos_labels, pos_values,
                "bottom-center", "where OSD popups appear on the screen"));
            placement.add(rows.int_row("osd.margin", "Margin from edge", 0, 400, 1, 76, "px from the screen's anchored edge"));
            page.add(placement);

            var size = new Adw.PreferencesGroup() { title = "Size" };
            size.add(rows.int_row("osd.width",  "Width",  100, 800, 1, 360, "long axis in px (the height on left/right positions)"));
            size.add(rows.int_row("osd.height", "Height", 24,  200, 1, 56,  "thickness in px (the width on left/right positions)"));
            page.add(size);

            var behavior = new Adw.PreferencesGroup() { title = "Behavior" };
            behavior.add(rows.int_row("osd.timeout-ms", "Timeout", 200, 10000, 100, 1500, "milliseconds before auto-dismiss"));
            page.add(behavior);

            var spacing = new Adw.PreferencesGroup() { title = "Spacing" };
            spacing.add(rows.int_row("osd.padding-x",       "Horizontal padding", 0, 100, 1, 22, "px of inner padding on the left and right"));
            spacing.add(rows.int_row("osd.padding-y",       "Vertical padding",   0, 100, 1, 10, "px of inner padding on the top and bottom"));
            spacing.add(rows.int_row("osd.content-spacing", "Content gap",        0, 60,  1, 14, "px between the icon, label, and progress bar"));
            page.add(spacing);

            var colors = new Adw.PreferencesGroup() { title = "Colors" };
            colors.add(rows.color_row("osd.background",     "OSD background", "#000000bf", "background of volume and brightness popups"));
            colors.add(rows.color_row("osd.text",           "OSD text",       "#ffffffff", "label and icon color on OSD popups"));
            colors.add(rows.color_row("osd.progress.track", "Progress track", "#ffffff26", "unfilled portion of the OSD progress bar"));
            colors.add(rows.color_row("osd.progress.fill",  "Progress fill",  "#ffffffff", "filled portion of the OSD progress bar"));
            page.add(colors);

            return page;
        }

        public override string? restart_target() { return "lumen-osd"; }
    }
}
