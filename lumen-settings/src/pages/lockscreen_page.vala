using Gtk;

namespace LumenSettings {

    // Lockscreen settings — writes ~/.config/lumen-shell/lockscreen.json, which
    // lumen-lockscreen reads via its Theme loader. Restarting lumen-lockscreen
    // re-reads the file.
    public class LockscreenPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "lockscreen"; } }
        public string title     { owned get { return "Lock Screen"; } }
        public string icon_name { owned get { return "system-lock-screen-symbolic"; } }

        JsonStore store;

        public Gtk.Widget build() {
            store = new JsonStore(Paths.lockscreen_json());

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            // --- Behaviour ---------------------------------------------------
            var behavior = new BoxedList("Behaviour");
            behavior.add_row(seconds_row("lockscreen.idle-timeout-ms", "Auto-lock when idle",
                0, 3600, 30, 300000, "seconds of inactivity before locking (0 = never)"));

            var pm_initial = store.get_bool("lockscreen.show-power-menu", true);
            var pm_row = new SwitchRow("Show power menu",
                "suspend / restart / shut down buttons on the lock screen", pm_initial);
            pm_row.toggled.connect((on) => {
                store.set_bool("lockscreen.show-power-menu", on);
                store.save();
            });
            behavior.add_row(pm_row);
            box.append(behavior);

            // --- Appearance --------------------------------------------------
            var look = new BoxedList("Appearance");
            look.add_row(int_row("lockscreen.blur-radius", "Backdrop blur",
                0, 64, 1, 12, "px of blur over the wallpaper backdrop"));
            look.add_row(color_row("lockscreen.scrim", "Scrim tint",
                "#00000059", "colour tinting the blurred backdrop"));
            look.add_row(color_row("lockscreen.accent", "Accent",
                "#ffffffeb", "highlight colour for the password field"));
            box.append(look);

            return box;
        }

        public override string? restart_target() { return "lumen-lockscreen"; }

        // ms stored, seconds shown.
        SpinRow seconds_row(string key, string label, double min_s, double max_s,
                            double step_s, int64 fallback_ms, string subtitle) {
            var initial_s = (double) store.get_int(key, fallback_ms) / 1000.0;
            var row = new SpinRow(label, min_s, max_s, step_s, initial_s, 0, subtitle);
            row.value_changed.connect((v) => {
                store.set_int(key, (int64) (v * 1000.0));
                store.save();
            });
            return row;
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
