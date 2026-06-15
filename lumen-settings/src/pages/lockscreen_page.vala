using Gtk;

namespace LumenSettings {

    // Lockscreen settings — writes ~/.config/lumen-shell/lockscreen.json, which
    // lumen-lockscreen reads via its Theme loader. The headline control is the
    // pre-lock transition effect (none / converge / flip); flip adds an axis
    // choice. Restarting lumen-lockscreen re-reads the file and re-selects the
    // effect (LockEffect.from_config()).
    //
    // The compositor-side phase of converge/flip is a Wayfire plugin
    // (wayfire-converge-lock / wayfire-flip-lock); only the plugin loaded in
    // wayfire.ini's [core] plugins actually animates the live desktop. The two
    // are mutually exclusive, so selecting an effect also swaps the matching
    // plugin into that list (and "none" removes both) — otherwise the IPC call
    // is a silent no-op and the effect never visibly takes hold. Mirrors how
    // DesktopPage swaps curtain/slide-peek.
    public class LockscreenPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "lockscreen"; } }
        public string title     { owned get { return "Lock Screen"; } }
        public string icon_name { owned get { return "system-lock-screen-symbolic"; } }

        JsonStore store;
        ComboRow axis_row;

#if WITH_WAYFIRE_CONFIG
        IniStore wf_store;
        const string CONVERGE_PLUGIN = "wayfire-converge-lock";
        const string FLIP_PLUGIN     = "wayfire-flip-lock";
#endif

        public Gtk.Widget build() {
            store = new JsonStore(Paths.lockscreen_json());
#if WITH_WAYFIRE_CONFIG
            wf_store = new IniStore(Paths.wayfire_ini());
#endif

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            // --- Transition effect ------------------------------------------
            var fx = new BoxedList("Unlock Transition");

            string[] fx_labels = { "None", "Converge", "Flip" };
            string[] fx_values = { "none", "converge", "flip" };
            var fx_initial = store.get_string("lockscreen.effect") ?? "converge";
            var fx_row = new ComboRow("Effect", fx_labels, fx_values, fx_initial,
                "animation played as the desktop hands off to the lock screen");
            fx_row.value_changed.connect((v) => {
                store.set_string("lockscreen.effect", v);
                store.save();
                axis_row.sensitive = (v == "flip");
#if WITH_WAYFIRE_CONFIG
                apply_effect_plugins(v);
#endif
            });
            fx.add_row(fx_row);

#if WITH_WAYFIRE_CONFIG
            // Reconcile the plugin list with the persisted effect on open, so a
            // config that drifted (effect=flip but only converge-lock loaded)
            // is healed without having to toggle the dropdown away and back.
            apply_effect_plugins(fx_initial);
#endif

            // Flip axis — only meaningful for the flip effect.
            string[] ax_labels = { "Vertical (Y)", "Horizontal (X)" };
            string[] ax_values = { "y", "x" };
            var ax_initial = store.get_string("lockscreen.flip-axis") ?? "y";
            axis_row = new ComboRow("Flip axis", ax_labels, ax_values, ax_initial,
                "axis the screen rotates about when flipping to the lock screen");
            axis_row.value_changed.connect((v) => {
                store.set_string("lockscreen.flip-axis", v);
                store.save();
            });
            axis_row.sensitive = (fx_initial == "flip");
            fx.add_row(axis_row);

            fx.add_row(int_row("lockscreen.effect-duration-ms", "Duration",
                100, 2000, 50, 300, "milliseconds the transition runs"));
            box.append(fx);

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

#if WITH_WAYFIRE_CONFIG
        // Load exactly the Wayfire plugin matching the chosen effect into
        // wayfire.ini's [core] plugins list: flip → wayfire-flip-lock, converge
        // → wayfire-converge-lock, none → neither. Preserves order, drops
        // duplicates, and only rewrites wayfire.ini when membership changes.
        void apply_effect_plugins(string effect) {
            var raw = wf_store.get_value("core", "plugins") ?? "";
            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<string>();
            foreach (var tok in raw.split(" ")) {
                var t = tok.strip();
                if (t == "") continue;
                if (!seen.contains(t)) { seen.add(t); ordered.add(t); }
            }

            bool want_flip     = (effect == "flip");
            bool want_converge = (effect == "converge");
            if (seen.contains(FLIP_PLUGIN) == want_flip &&
                seen.contains(CONVERGE_PLUGIN) == want_converge)
                return;   // already in sync — leave wayfire.ini untouched

            set_in_list(ordered, seen, FLIP_PLUGIN,     want_flip);
            set_in_list(ordered, seen, CONVERGE_PLUGIN, want_converge);

            var sb = new StringBuilder();
            for (int i = 0; i < ordered.size; i++) {
                if (i > 0) sb.append(" ");
                sb.append(ordered.get(i));
            }
            wf_store.set_value("core", "plugins", sb.str);
            wf_store.save();
        }

        static void set_in_list(Gee.ArrayList<string> ordered,
                                Gee.HashSet<string> seen, string name, bool on) {
            if (on) {
                if (!seen.contains(name)) { seen.add(name); ordered.add(name); }
            } else {
                ordered.remove(name);
                seen.remove(name);
            }
        }
#endif

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
