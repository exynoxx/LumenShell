using Gtk;

namespace LumenSettings {

    public class DesktopPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "desktop"; } }
        public string title     { owned get { return "Desktop"; } }
        public string icon_name { owned get { return "view-grid-symbolic"; } }

        IniStore store;
        const string SECTION = "desktop";

#if WITH_WAYFIRE_CONFIG
        IniStore wf_store;
        const string CURTAIN_PLUGIN = "wayfire-curtain-peek";
        const string SLIDE_PLUGIN   = "wayfire-slide-peek";
        const string SLIDE_SECTION  = "wayfire-slide-peek";
#endif

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

#if WITH_WAYFIRE_CONFIG
            // App-drawer reveal: pick curtain (doors) vs slide-down and the
            // slide's direction. The two reveals are mutually
            // exclusive — enabling one disables the other in wayfire.ini's
            // [core] plugins list, so only one is ever loaded at a time.
            wf_store = new IniStore(Paths.wayfire_ini());

            var reveal = new BoxedList("App drawer reveal");

            string[] style_labels = { "Curtain (doors)", "Slide-down" };
            string[] style_values = { "curtain", "slide" };
            var style_initial = plugin_enabled(SLIDE_PLUGIN) ? "slide" : "curtain";
            var style_row = new ComboRow("Reveal style", style_labels, style_values, style_initial,
                "animation used to reveal the app drawer");
            style_row.value_changed.connect((v) => {
                bool slide = (v == "slide");
                set_plugin_enabled(SLIDE_PLUGIN,   slide);
                set_plugin_enabled(CURTAIN_PLUGIN, !slide);
            });
            reveal.add_row(style_row);

            string[] dir_labels = { "Down from top", "Up from bottom" };
            string[] dir_values = { "top", "bottom" };
            var dir_initial = wf_store.get_value(SLIDE_SECTION, "direction") ?? "top";
            var dir_row = new ComboRow("Slide direction", dir_labels, dir_values, dir_initial,
                "edge the drawer slides in from (slide-down reveal only)");
            dir_row.value_changed.connect((v) => {
                wf_store.set_value(SLIDE_SECTION, "direction", v);
                wf_store.save();
            });
            reveal.add_row(dir_row);

            box.append(reveal);
#endif

            return box;
        }

        public override string? restart_target() { return "lumen-desktop"; }

#if WITH_WAYFIRE_CONFIG
        bool plugin_enabled(string name) {
            var raw = wf_store.get_value("core", "plugins") ?? "";
            foreach (var tok in raw.split(" ")) {
                if (tok.strip() == name) return true;
            }
            return false;
        }

        // Add/remove a plugin from wayfire.ini's [core] plugins list, preserving
        // order and dropping duplicates.
        void set_plugin_enabled(string name, bool on) {
            var raw = wf_store.get_value("core", "plugins") ?? "";
            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<string>();
            foreach (var tok in raw.split(" ")) {
                var t = tok.strip();
                if (t == "") continue;
                if (!seen.contains(t)) { seen.add(t); ordered.add(t); }
            }
            if (on) {
                if (!seen.contains(name)) ordered.add(name);
            } else {
                ordered.remove(name);
            }
            var sb = new StringBuilder();
            for (int i = 0; i < ordered.size; i++) {
                if (i > 0) sb.append(" ");
                sb.append(ordered.get(i));
            }
            wf_store.set_value("core", "plugins", sb.str);
            wf_store.save();
        }
#endif

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
