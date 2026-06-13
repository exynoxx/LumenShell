using Gee;
using GLib;

namespace LumenSettings {

    /* One available mode of an output. */
    public class OutputMode : GLib.Object {
        public int    width;
        public int    height;
        public double refresh;     // Hz, e.g. 59.951
        public bool   preferred;
        public bool   current;

        // Argument for `wlr-randr --mode` (Hz form).
        public string to_arg() {
            return "%dx%d@%.3fHz".printf(width, height, refresh);
        }
        // Value for wayfire.ini `mode =` (Wayfire wants millihertz).
        public string to_wayfire_arg() {
            return "%dx%d@%d".printf(width, height, (int) Math.round(refresh * 1000));
        }
        public string res_key() { return "%dx%d".printf(width, height); }
        public string refresh_label() { return "%.2f Hz".printf(refresh); }
        public string label() {
            return "%d × %d  @ %.2f Hz".printf(width, height, refresh);
        }
    }

    public enum OutputTransform {
        NORMAL, ROT_90, ROT_180, ROT_270,
        FLIPPED, FLIPPED_90, FLIPPED_180, FLIPPED_270;

        public string to_arg() {
            switch (this) {
                case ROT_90:      return "90";
                case ROT_180:     return "180";
                case ROT_270:     return "270";
                case FLIPPED:     return "flipped";
                case FLIPPED_90:  return "flipped-90";
                case FLIPPED_180: return "flipped-180";
                case FLIPPED_270: return "flipped-270";
                default:          return "normal";
            }
        }
        public string label() {
            switch (this) {
                case ROT_90:      return "90° (portrait right)";
                case ROT_180:     return "180° (upside down)";
                case ROT_270:     return "270° (portrait left)";
                case FLIPPED:     return "Flipped";
                case FLIPPED_90:  return "Flipped 90°";
                case FLIPPED_180: return "Flipped 180°";
                case FLIPPED_270: return "Flipped 270°";
                default:          return "Landscape (normal)";
            }
        }
        // True when the transform swaps width/height (portrait).
        public bool is_portrait() {
            return this == ROT_90 || this == ROT_270
                || this == FLIPPED_90 || this == FLIPPED_270;
        }
        public static OutputTransform parse(string s) {
            switch (s.strip()) {
                case "90":          return ROT_90;
                case "180":         return ROT_180;
                case "270":         return ROT_270;
                case "flipped":     return FLIPPED;
                case "flipped-90":  return FLIPPED_90;
                case "flipped-180": return FLIPPED_180;
                case "flipped-270": return FLIPPED_270;
                default:            return NORMAL;
            }
        }
        public static OutputTransform from_index(int i) {
            return (OutputTransform) i;
        }
    }

    /* Live state of one connected output, as reported by wlr-randr. */
    public class OutputInfo : GLib.Object {
        public string name;          // connector, e.g. "HDMI-A-1"
        public string description;
        public Gee.ArrayList<OutputMode> modes = new Gee.ArrayList<OutputMode>();
        public OutputMode? current_mode;
        public int    pos_x;
        public int    pos_y;
        public OutputTransform transform = OutputTransform.NORMAL;
        public bool   enabled = true;
        public double scale = 1.0;   // read-only; not exposed in UI yet

        // Effective on-screen size given the current mode + transform.
        public int eff_width() {
            if (current_mode == null) return 0;
            return transform.is_portrait() ? current_mode.height : current_mode.width;
        }
        public int eff_height() {
            if (current_mode == null) return 0;
            return transform.is_portrait() ? current_mode.width : current_mode.height;
        }

        public OutputInfo clone() {
            var o = new OutputInfo();
            o.name = name; o.description = description;
            o.pos_x = pos_x; o.pos_y = pos_y;
            o.transform = transform; o.enabled = enabled; o.scale = scale;
            foreach (var m in modes) {
                var nm = new OutputMode();
                nm.width = m.width; nm.height = m.height; nm.refresh = m.refresh;
                nm.preferred = m.preferred; nm.current = m.current;
                o.modes.add(nm);
                if (current_mode == m) o.current_mode = nm;
            }
            // Fallback: match by value if reference didn't line up.
            if (o.current_mode == null && current_mode != null) {
                foreach (var m in o.modes) {
                    if (m.width == current_mode.width && m.height == current_mode.height
                        && Math.fabs(m.refresh - current_mode.refresh) < 0.01) {
                        o.current_mode = m; break;
                    }
                }
            }
            return o;
        }

        // Distinct resolutions in descending order (by area).
        public Gee.ArrayList<string> resolutions() {
            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<OutputMode>();
            foreach (var m in modes) {
                if (!seen.contains(m.res_key())) {
                    seen.add(m.res_key());
                    ordered.add(m);
                }
            }
            ordered.sort((a, b) => (b.width * b.height) - (a.width * a.height));
            var keys = new Gee.ArrayList<string>();
            foreach (var m in ordered) keys.add(m.res_key());
            return keys;
        }

        // Refresh rates available for a given resolution, descending.
        public Gee.ArrayList<OutputMode> modes_for(string res_key) {
            var list = new Gee.ArrayList<OutputMode>();
            foreach (var m in modes) {
                if (m.res_key() == res_key) list.add(m);
            }
            list.sort((a, b) => (int) Math.round((b.refresh - a.refresh) * 1000));
            return list;
        }
    }

    /* Thin wrapper over the `wlr-randr` CLI (Wayfire implements
     * wlr-output-management-v1, so this works under it). Mirrors the
     * shell-out style of nmcli.vala / pactl.vala. */
    public class WlrRandr : GLib.Object {

        public static bool available() {
            return Environment.find_program_in_path("wlr-randr") != null;
        }

        // Inherit the real environment (WAYLAND_DISPLAY, XDG_RUNTIME_DIR, …) and
        // only pin LC_ALL — a bare {"LC_ALL=C"} would wipe the Wayland env and
        // wlr-randr would fail to connect to the compositor.
        static string[] c_locale_env() {
            var env = Environ.get();
            return Environ.set_variable(env, "LC_ALL", "C", true);
        }

        public Gee.ArrayList<OutputInfo> enumerate() {
            var outs = new Gee.ArrayList<OutputInfo>();
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

            OutputInfo? cur = null;
            bool in_modes = false;
            foreach (var raw in outp.split("\n")) {
                if (raw.strip() == "") continue;
                bool indented = raw.has_prefix(" ") || raw.has_prefix("\t");
                var line = raw.strip();

                if (!indented) {
                    // New output: "NAME \"Description\""
                    in_modes = false;
                    cur = new OutputInfo();
                    int q = line.index_of_char('"');
                    if (q >= 0) {
                        cur.name = line.substring(0, q).strip();
                        cur.description = line.substring(q).replace("\"", "").strip();
                    } else {
                        cur.name = line;
                        cur.description = line;
                    }
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
                } else if (line.has_prefix("Transform:")) {
                    cur.transform = OutputTransform.parse(line.substring(10).strip());
                } else if (line.has_prefix("Scale:")) {
                    cur.scale = double.parse(line.substring(6).strip());
                }
            }
            return outs;
        }

        // "1920x1080 px, 60.000000 Hz (preferred, current)"
        void parse_mode_line(OutputInfo o, string line) {
            var m = new OutputMode();
            var parts = line.split(",");
            if (parts.length < 2) return;
            // resolution
            var res = parts[0].replace("px", "").strip().split("x");
            if (res.length != 2) return;
            m.width  = int.parse(res[0].strip());
            m.height = int.parse(res[1].strip());
            // refresh
            var hz = parts[1].replace("Hz", "");
            // strip any trailing "(...)" if it landed here
            int paren = hz.index_of_char('(');
            if (paren >= 0) hz = hz.substring(0, paren);
            m.refresh = double.parse(hz.strip());
            // flags (could be in parts[2] or appended)
            m.preferred = line.contains("preferred");
            m.current   = line.contains("current");
            o.modes.add(m);
            if (m.current) o.current_mode = m;
        }

        // Apply a whole layout in one wlr-randr invocation (atomic). Returns
        // null on success, or wlr-randr's error text (for the UI) on failure.
        public string? apply_all(Gee.ArrayList<OutputInfo> outs) {
            var argv = new Gee.ArrayList<string>();
            argv.add("wlr-randr");
            foreach (var o in outs) {
                argv.add("--output"); argv.add(o.name);
                if (!o.enabled) {
                    argv.add("--off");
                    continue;
                }
                argv.add("--on");
                if (o.current_mode != null) {
                    argv.add("--mode"); argv.add(o.current_mode.to_arg());
                }
                argv.add("--pos"); argv.add("%d,%d".printf(o.pos_x, o.pos_y));
                argv.add("--transform"); argv.add(o.transform.to_arg());
            }
            string[] args = argv.to_array();
            string outp, errp;
            int status;
            try {
                Process.spawn_sync(null, args, c_locale_env(),
                    SpawnFlags.SEARCH_PATH, null, out outp, out errp, out status);
            } catch (SpawnError e) {
                warning("wlr-randr apply: %s", e.message);
                return e.message;
            }
            // exit_status is a raw waitpid() status — interpret it properly
            // rather than comparing to 0 directly.
            try {
                Process.check_wait_status(status);
            } catch (Error e) {
                var detail = (errp != null && errp.strip() != "") ? errp.strip() : e.message;
                warning("wlr-randr apply failed: %s\n  cmd: %s", detail, string.joinv(" ", args));
                return detail;
            }
            return null;
        }
    }
}
