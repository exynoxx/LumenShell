using LumenCommon;
using Gtk;

namespace LumenSettings {

    public class DrawerPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "drawer"; } }
        public string title     { owned get { return "Drawer"; } }
        public string icon_name { owned get { return "view-grid-symbolic"; } }

        IniRows rows;

#if WITH_WAYFIRE_CONFIG
        IniStore wf_store;
        IniRows  slide_rows;
        const string CURTAIN_PLUGIN = "wayfire-curtain-peek";
        const string SLIDE_PLUGIN   = "wayfire-slide-peek";
        const string SLIDE_SECTION  = "wayfire-slide-peek";
#endif

        public Gtk.Widget build() {
            rows = new IniRows(Paths.drawer_ini(), "drawer");

            var page = new Adw.PreferencesPage();

            var group = new Adw.PreferencesGroup() { title = "App grid" };
            group.add(rows.int_row("grid.cols",   "Columns", 1, 12, 1, 6, "number of app icons per row"));
            group.add(rows.int_row("grid.rows",   "Rows",    1, 8,  1, 4, "number of app icon rows per page"));
            group.add(rows.int_row("grid.margin", "Page margin", 0, 400, 1, 130, "px of empty space around the grid, on every edge"));
            page.add(group);

            // The app drawer is always placed on every connected monitor: the
            // curtain/slide peek is per-output, so a grid must exist on each
            // output for a peek there to reveal anything. (No toggle — a missing
            // grid on the peeked monitor would just show the grey backdrop.)

#if WITH_WAYFIRE_CONFIG
            // App-drawer reveal: pick curtain (doors) vs slide-down and the
            // slide's direction. The two reveals are mutually
            // exclusive — enabling one disables the other in wayfire.ini's
            // [core] plugins list, so only one is ever loaded at a time.
            wf_store   = new IniStore(Paths.wayfire_ini());
            slide_rows = new IniRows(Paths.wayfire_ini(), SLIDE_SECTION);

            var reveal = new Adw.PreferencesGroup() { title = "App drawer reveal" };

            string[] style_labels = { "Curtain (doors)", "Slide-down" };
            string[] style_values = { "curtain", "slide" };
            var style_initial =
                Wayfire.PluginList.is_enabled(wf_store, SLIDE_PLUGIN) ? "slide" : "curtain";
            var style_row = new ComboRow("Reveal style", style_labels, style_values, style_initial,
                "animation used to reveal the app drawer");
            style_row.value_changed.connect((v) => {
                bool slide = (v == "slide");
                Wayfire.PluginList.set_enabled(wf_store, SLIDE_PLUGIN,   slide);
                Wayfire.PluginList.set_enabled(wf_store, CURTAIN_PLUGIN, !slide);
            });
            reveal.add(style_row);

            string[] dir_labels = { "Down from top", "Up from bottom" };
            string[] dir_values = { "top", "bottom" };
            reveal.add(slide_rows.combo_row("direction", "Slide direction",
                dir_labels, dir_values, "top",
                "edge the drawer slides in from (slide-down reveal only)"));

            page.add(reveal);
#endif

            return page;
        }

        public override string? restart_target() { return "lumen-drawer"; }
    }
}
