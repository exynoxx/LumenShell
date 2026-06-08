using Gtk;

namespace LumenSettings {

    public class PanelPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "panel"; } }
        public string title     { owned get { return "Panel"; } }
        public string icon_name { owned get { return "preferences-system-symbolic"; } }

        IniStore store;
        JsonStore theme;
        const string SECTION = "panel";

        // Auto-hide backdrop reuses the panel color's RGB with its own alpha;
        // these track the latest values so either control can rebuild the hex.
        Gdk.RGBA panel_rgba;
        int autohide_opacity;

        public Gtk.Widget build() {
            store = new IniStore(Paths.panel_ini());
            theme = new JsonStore(Paths.theme_json());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var layout = new BoxedList("Layout");
            var height_initial = parse_double(store.get_value(SECTION, "panel.height"), 60);
            var height_row = new SpinRow("Panel height", 40, 120, 1, height_initial, 0, "panel thickness in px");
            height_row.value_changed.connect((v) => {
                store.set_value(SECTION, "panel.height", "%d".printf((int) v));
                store.save();
            });
            layout.add_row(height_row);
            box.append(layout);

            var colors = new BoxedList("Colors");

            var panel_bg_initial = theme.get_string("panel.background") ?? "#1a1d27ff";
            panel_rgba = parse_rgba(panel_bg_initial);
            var autohide_initial = theme.get_string("panel.autohide-background");
            autohide_opacity = autohide_initial != null
                ? (int) (parse_rgba(autohide_initial).alpha * 100 + 0.5)
                : 50;

            var panel_bg_row = new ColorRow("Panel background", panel_bg_initial,
                "panel color, including transparency");
            panel_bg_row.value_changed.connect((hex) => {
                panel_rgba = parse_rgba(hex);
                theme.set_string("panel.background", hex);
                theme.set_string("panel.autohide-background", autohide_hex());
                theme.save();
            });
            colors.add_row(panel_bg_row);

            var autohide_row = new SpinRow("Auto-hide opacity", 0, 100, 1, autohide_opacity, 0,
                "panel transparency while auto-hidden (reuses the panel color)");
            autohide_row.value_changed.connect((v) => {
                autohide_opacity = (int) v;
                theme.set_string("panel.autohide-background", autohide_hex());
                theme.save();
            });
            colors.add_row(autohide_row);

            colors.add_row(color_row("tray.background",       "Tray background",       "#222633ff", "tray icon background when not hovered"));
            colors.add_row(color_row("tray.icon-hover",       "Tray icon hover",       "#2c3140ff", "tray icon background while the pointer is over it"));
            colors.add_row(color_row("app.hover",             "App hover",             "#2c3140ff", "taskbar app background while the pointer is over it"));
            colors.add_row(color_row("app.launching",         "App launching",         "#3d7affff", "taskbar app background while the app is starting up"));
            colors.add_row(color_row("app.active-underline",  "Active app underline",  "#3d7affff", "underline color shown beneath the focused app"));
            box.append(colors);

            var clock_group = new BoxedList("Clock");

            var fmt_initial = store.get_value(SECTION, "clock.format") ?? "%H:%M";
            var fmt_row = new EntryRow("Format", fmt_initial, "strftime pattern, e.g. %H:%M or %Y-%m-%d %H:%M");
            fmt_row.value_changed.connect((v) => {
                store.set_value(SECTION, "clock.format", v);
                store.save();
            });
            clock_group.add_row(fmt_row);

            string[] click_labels = { "Do nothing", "Open calendar", "Run command" };
            string[] click_values = { "none", "open-calendar", "run-command" };
            var click_initial = store.get_value(SECTION, "clock.on-click") ?? "none";
            var click_row = new ComboRow("On click", click_labels, click_values, click_initial, "action to run when the clock is clicked");
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

            var behavior_group = new BoxedList("Behavior");
            var auto_hide_initial = (store.get_value(SECTION, "behavior.auto-hide") ?? "false") == "true";
            var auto_hide_row = new SwitchRow("Auto-hide panel",
                "Hide the panel and reveal it when the pointer reaches the bottom edge",
                auto_hide_initial);
            auto_hide_row.toggled.connect((v) => {
                store.set_value(SECTION, "behavior.auto-hide", v ? "true" : "false");
                store.save();
            });
            behavior_group.add_row(auto_hide_row);

            var restart_row = new ActionRow("Restart panel",
                "Kill the running panel and relaunch it to apply changes");
            var restart_btn = new Gtk.Button.with_label("Restart");
            restart_btn.add_css_class("suggested-action");
            restart_btn.clicked.connect(() => {
                try {
                    // setsid -f fully detaches the new panel so it outlives
                    // lumen-settings; the sleep lets the old surface tear down.
                    GLib.Process.spawn_command_line_async(
                        "sh -c 'pkill -x lumen-panel; sleep 0.3; setsid -f lumen-panel'");
                } catch (GLib.SpawnError e) {
                    warning("lumen-settings: failed to restart panel: %s", e.message);
                }
            });
            restart_row.set_suffix(restart_btn);
            behavior_group.add_row(restart_row);

            box.append(behavior_group);

            return box;
        }

        static double parse_double(string? s, double fallback) {
            if (s == null) return fallback;
            double d;
            return double.try_parse(s, out d) ? d : fallback;
        }

        ColorRow color_row(string key, string label, string fallback, string subtitle) {
            var initial = theme.get_string(key) ?? fallback;
            var row = new ColorRow(label, initial, subtitle);
            row.value_changed.connect((hex) => {
                theme.set_string(key, hex);
                theme.save();
            });
            return row;
        }

        // Auto-hide backdrop = the panel color's RGB with the auto-hide alpha.
        string autohide_hex() {
            return "#%02X%02X%02X%02X".printf(
                (uint) (panel_rgba.red   * 255 + 0.5),
                (uint) (panel_rgba.green * 255 + 0.5),
                (uint) (panel_rgba.blue  * 255 + 0.5),
                (uint) (autohide_opacity * 255 / 100));
        }

        static Gdk.RGBA parse_rgba(string s) {
            var c = Gdk.RGBA();
            if (!c.parse(s)) { c.red = 0; c.green = 0; c.blue = 0; c.alpha = 1; }
            return c;
        }
    }
}
