using GLib;

/* Win+P display-mode switching. Reads the live output layout from `wlr-randr`
 * (the same tool lumen-settings uses), classifies outputs as internal vs
 * external, and applies one of three modes in a single atomic wlr-randr call.
 *
 * This is a transient/live toggle: it does NOT rewrite ~/.config/wayfire.ini
 * [output:*] sections, so it never fights the persistent layout owned by the
 * lumen-settings display page. */
public class DisplayCtl {

    public enum Mode {
        INTERNAL_ONLY,
        EXTEND,
        EXTERNAL_ONLY;

        public string label() {
            switch (this) {
                case INTERNAL_ONLY: return "Built-in display";
                case EXTERNAL_ONLY: return "External display";
                default:            return "Extend";
            }
        }
        // Symbolic icons, all shipped by Adwaita.
        public string icon() {
            switch (this) {
                case INTERNAL_ONLY: return "video-single-display-symbolic";
                case EXTERNAL_ONLY: return "video-display-symbolic";
                default:            return "video-joined-displays-symbolic";
            }
        }
        public static Mode? parse(string s) {
            switch (s.down()) {
                case "internal": return INTERNAL_ONLY;
                case "extend":   return EXTEND;
                case "external": return EXTERNAL_ONLY;
                default:         return null;
            }
        }
    }

    /* One available mode of an output. */
    private class OutMode {
        public int    width;
        public int    height;
        public double refresh;     // Hz
        public bool   preferred;
        public bool   current;

        // Locale-independent argument for `wlr-randr --mode`. Built from integer
        // millihertz so it never picks up a locale decimal separator (da_DK would
        // otherwise yield "59,951" via %.3f, which wlr-randr rejects).
        public string to_arg() {
            int mhz = (int) Math.round(refresh * 1000);
            return "%dx%d@%d.%03dHz".printf(width, height, mhz / 1000, mhz % 1000);
        }
    }

    /* Live state of one connected output, as reported by wlr-randr. */
    private class Out {
        public string name;
        public bool   enabled = true;   // wlr-randr only lists connected outputs
        public int    pos_x;
        public int    pos_y;
        public GLib.GenericArray<OutMode> modes = new GLib.GenericArray<OutMode>();
        public OutMode? current_mode;

        // Laptop panels: eDP / LVDS / DSI. Everything else (HDMI/DP/DVI/…) external.
        public bool is_internal() {
            string u = name.up();
            return u.has_prefix("EDP") || u.has_prefix("LVDS") || u.has_prefix("DSI");
        }
        public OutMode? pick_mode() {
            if (current_mode != null) return current_mode;
            for (int i = 0; i < modes.length; i++)
                if (modes.get(i).preferred) return modes.get(i);
            return modes.length > 0 ? modes.get(0) : null;
        }
        public int width_px() {
            var m = pick_mode();
            return m != null ? m.width : 0;
        }
    }

    // Inherit the real environment (WAYLAND_DISPLAY, XDG_RUNTIME_DIR, …) and only
    // pin LC_ALL — a bare {"LC_ALL=C"} would wipe the Wayland env and wlr-randr
    // would fail to connect to the compositor.
    private static string[] c_locale_env() {
        var env = Environ.get();
        return Environ.set_variable(env, "LC_ALL", "C", true);
    }

    private static GLib.GenericArray<Out> enumerate() {
        var outs = new GLib.GenericArray<Out>();
        string outp, errp;
        int status;
        try {
            Process.spawn_sync(null,
                { "wlr-randr" },
                c_locale_env(),
                SpawnFlags.SEARCH_PATH,
                null, out outp, out errp, out status);
        } catch (SpawnError e) {
            warning("wlr-randr: %s", e.message);
            return outs;
        }
        if (outp == null) return outs;

        Out? cur = null;
        bool in_modes = false;
        foreach (var raw in outp.split("\n")) {
            if (raw.strip() == "") continue;
            bool indented = raw.has_prefix(" ") || raw.has_prefix("\t");
            var line = raw.strip();

            if (!indented) {
                // New output: "NAME \"Description\""
                in_modes = false;
                cur = new Out();
                int q = line.index_of_char('"');
                cur.name = (q >= 0) ? line.substring(0, q).strip() : line;
                outs.add(cur);
                continue;
            }
            if (cur == null) continue;

            if (line == "Modes:") { in_modes = true; continue; }

            if (in_modes && (line.has_prefix("Position:")
                          || line.has_prefix("Transform:")
                          || line.has_prefix("Scale:")
                          || line.has_prefix("Enabled:")
                          || line.has_prefix("Adaptive"))) {
                in_modes = false;
            }

            if (in_modes) {
                parse_mode_line(cur, line);
                continue;
            }

            if (line.has_prefix("Enabled:")) {
                cur.enabled = line.substring(8).strip().down().has_prefix("yes");
            } else if (line.has_prefix("Position:")) {
                var pv = line.substring(9).strip().split(",");
                if (pv.length == 2) {
                    cur.pos_x = int.parse(pv[0].strip());
                    cur.pos_y = int.parse(pv[1].strip());
                }
            }
        }
        return outs;
    }

    // "1920x1080 px, 60.000000 Hz (preferred, current)"
    private static void parse_mode_line(Out o, string line) {
        var m = new OutMode();
        var parts = line.split(",");
        if (parts.length < 2) return;
        var res = parts[0].replace("px", "").strip().split("x");
        if (res.length != 2) return;
        m.width  = int.parse(res[0].strip());
        m.height = int.parse(res[1].strip());
        var hz = parts[1].replace("Hz", "");
        int paren = hz.index_of_char('(');
        if (paren >= 0) hz = hz.substring(0, paren);
        m.refresh   = double.parse(hz.strip());
        m.preferred = line.contains("preferred");
        m.current   = line.contains("current");
        o.modes.add(m);
        if (m.current) o.current_mode = m;
    }

    private static bool has_internal(GLib.GenericArray<Out> outs) {
        for (int i = 0; i < outs.length; i++)
            if (outs.get(i).is_internal()) return true;
        return false;
    }
    private static bool has_external(GLib.GenericArray<Out> outs) {
        for (int i = 0; i < outs.length; i++)
            if (!outs.get(i).is_internal()) return true;
        return false;
    }

    private static Mode current_state(GLib.GenericArray<Out> outs) {
        bool internal_on = false, external_on = false;
        for (int i = 0; i < outs.length; i++) {
            var o = outs.get(i);
            if (!o.enabled) continue;
            if (o.is_internal()) internal_on = true;
            else external_on = true;
        }
        if (internal_on && !external_on) return Mode.INTERNAL_ONLY;
        if (external_on && !internal_on) return Mode.EXTERNAL_ONLY;
        return Mode.EXTEND;   // both on (or, defensively, none)
    }

    // Never produce a layout that blanks every screen.
    private static Mode resolve(GLib.GenericArray<Out> outs, Mode mode) {
        if (mode == Mode.INTERNAL_ONLY && !has_internal(outs)) return Mode.EXTERNAL_ONLY;
        if (mode == Mode.EXTERNAL_ONLY && !has_external(outs)) return Mode.INTERNAL_ONLY;
        return mode;
    }

    // Build a single wlr-randr invocation for `mode` and run it.
    private static bool build_and_run(GLib.GenericArray<Out> outs, Mode mode) {
        // Deterministic placement order: internal first, then externals.
        var ordered = new GLib.GenericArray<Out>();
        for (int i = 0; i < outs.length; i++)
            if (outs.get(i).is_internal()) ordered.add(outs.get(i));
        for (int i = 0; i < outs.length; i++)
            if (!outs.get(i).is_internal()) ordered.add(outs.get(i));

        var argv = new GLib.GenericArray<string>();
        argv.add("wlr-randr");
        int x = 0;
        for (int i = 0; i < ordered.length; i++) {
            var o = ordered.get(i);
            bool on;
            switch (mode) {
                case Mode.INTERNAL_ONLY: on =  o.is_internal(); break;
                case Mode.EXTERNAL_ONLY: on = !o.is_internal(); break;
                default:                 on =  true;            break;   // EXTEND
            }
            argv.add("--output"); argv.add(o.name);
            if (!on) {
                argv.add("--off");
                continue;
            }
            argv.add("--on");
            var m = o.pick_mode();
            if (m != null) { argv.add("--mode"); argv.add(m.to_arg()); }
            argv.add("--pos"); argv.add("%d,0".printf(x));
            x += (o.width_px() > 0) ? o.width_px() : (m != null ? m.width : 0);
        }

        // GenericArray.data is NOT NULL-terminated; spawn_sync needs a
        // NULL-terminated argv, so copy into a fresh array (last slot stays null).
        var args = new string[argv.length + 1];
        for (int i = 0; i < argv.length; i++) args[i] = argv.get(i);
        return run_wlr(args);
    }

    private static bool run_wlr(string[] args) {
        string outp, errp;
        int status;
        try {
            Process.spawn_sync(null, args, c_locale_env(),
                SpawnFlags.SEARCH_PATH, null, out outp, out errp, out status);
        } catch (SpawnError e) {
            warning("wlr-randr apply: %s", e.message);
            return false;
        }
        try {
            Process.check_wait_status(status);
        } catch (Error e) {
            warning("wlr-randr apply failed: %s",
                (errp != null && errp.strip() != "") ? errp.strip() : e.message);
            return false;
        }
        return true;
    }

    // Apply a specific mode. Returns the mode actually applied (after guards),
    // or null on failure / no outputs.
    public static Mode? apply(Mode requested) {
        var outs = enumerate();
        if (outs.length == 0) {
            warning("wlr-randr listed no outputs (not running under Wayfire?)");
            return null;
        }
        var mode = resolve(outs, requested);
        if (!build_and_run(outs, mode)) return null;
        return mode;
    }

    // The mode the live layout currently represents (used to seed the Win+P
    // selector highlight). null if no outputs are visible to wlr-randr.
    public static Mode? current() {
        var outs = enumerate();
        if (outs.length == 0) return null;
        return current_state(outs);
    }

    // Advance to the next mode: INTERNAL_ONLY → EXTEND → EXTERNAL_ONLY → …
    // With no external display connected, stays on INTERNAL_ONLY.
    public static Mode? cycle() {
        var outs = enumerate();
        if (outs.length == 0) {
            warning("wlr-randr listed no outputs (not running under Wayfire?)");
            return null;
        }
        Mode next;
        if (!has_external(outs)) {
            next = Mode.INTERNAL_ONLY;
        } else if (!has_internal(outs)) {
            next = Mode.EXTERNAL_ONLY;   // only externals — nothing to cycle to
        } else {
            switch (current_state(outs)) {
                case Mode.INTERNAL_ONLY: next = Mode.EXTEND;        break;
                case Mode.EXTEND:        next = Mode.EXTERNAL_ONLY; break;
                default:                 next = Mode.INTERNAL_ONLY; break;
            }
        }
        if (!build_and_run(outs, next)) return null;
        return next;
    }
}
