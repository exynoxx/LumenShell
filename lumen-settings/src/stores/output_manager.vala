using LumenCommon;

namespace LumenSettings {

    public class OutputMode : GLib.Object {
        public int    width;
        public int    height;
        public double refresh;     // Hz, e.g. 59.951

        // Built from integer mHz: %.3f would emit "59,951" under da_DK etc.
        public string refresh_key() {
            int mhz = (int) Math.round(refresh * 1000);
            return "%d.%03d".printf(mhz / 1000, mhz % 1000);
        }
        // Human/diagnostic form ("2560x1440@59.951Hz").
        public string to_arg() {
            return "%dx%d@%sHz".printf(width, height, refresh_key());
        }
        // Value for wayfire.ini `mode =` (Wayfire wants millihertz).
        public string to_wayfire_arg() {
            return "%dx%d@%d".printf(width, height, (int) Math.round(refresh * 1000));
        }
        public int refresh_mhz() { return (int) Math.round(refresh * 1000); }
        public string res_key() { return "%dx%d".printf(width, height); }
        public string refresh_label() { return "%.2f Hz".printf(refresh); }
    }

    // Order matches wl_output.transform; values are cast straight to the protocol int.
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
        public static OutputTransform from_index(int i) {
            if (i < 0 || i > 7) return NORMAL;
            return (OutputTransform) i;
        }
    }

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

    public class OutputManager : GLib.Object {

        bool initialized = false;

        // Returns true if the compositor exposes wlr-output-management-v1.
        public bool init() {
            if (initialized) return WLHooks.output_mgmt_available();
            initialized = true;

            var gdk = Gdk.Display.get_default();
            if (!(gdk is Gdk.Wayland.Display)) {
                DiagLog.log("output_mgmt: not running on Wayland — unavailable");
                return false;
            }
            unowned Wl.Display wl = ((Gdk.Wayland.Display) gdk).get_wl_display();
            int rc = WLHooks.output_mgmt_init(wl);
            DiagLog.log("output_mgmt: init rc=%d available=%s",
                rc, WLHooks.output_mgmt_available().to_string());
            return WLHooks.output_mgmt_available();
        }

        public bool available() { return WLHooks.output_mgmt_available(); }

        public Gee.ArrayList<OutputInfo> enumerate() {
            WLHooks.output_mgmt_refresh();

            var outs = new Gee.ArrayList<OutputInfo>();
            var idxs = new Gee.ArrayList<int>();
            WLHooks.output_mgmt_for_each_head((idx, name, desc, enabled, x, y, transform, scale) => {
                var o = new OutputInfo();
                o.name = name; o.description = desc;
                o.enabled = enabled;
                o.pos_x = x; o.pos_y = y;
                o.transform = OutputTransform.from_index(transform);
                o.scale = scale;
                outs.add(o);
                idxs.add(idx);
            });

            for (int i = 0; i < outs.size; i++) {
                var o = outs.get(i);
                WLHooks.output_mgmt_for_each_mode(idxs.get(i), (hidx, w, h, mhz, preferred, current) => {
                    var m = new OutputMode();
                    m.width = w; m.height = h; m.refresh = mhz / 1000.0;
                    o.modes.add(m);
                    if (current) o.current_mode = m;
                });
            }

            DiagLog.log("enumerate: %d output(s):", outs.size);
            foreach (var o in outs) {
                DiagLog.log("    %s \"%s\"  enabled=%s  modes=%d  current=%s  pos=%d,%d  transform=%s  scale=%.2f",
                    o.name, o.description, o.enabled.to_string(), o.modes.size,
                    o.current_mode != null ? o.current_mode.to_arg() : "(none)",
                    o.pos_x, o.pos_y, o.transform.to_arg(), o.scale);
            }
            return outs;
        }

        // Apply a whole layout in one atomic configuration. Returns null on
        // success, or a human-readable error (for the UI) on failure.
        public string? apply_all(Gee.ArrayList<OutputInfo> outs) {
            DiagLog.log("apply: configuring %d output(s)", outs.size);
            WLHooks.output_mgmt_refresh();

            int rc = WLHooks.output_mgmt_config_begin();
            if (rc != 0) {
                // No serial yet — drain once and retry.
                WLHooks.output_mgmt_refresh();
                rc = WLHooks.output_mgmt_config_begin();
            }
            if (rc != 0) {
                DiagLog.log("apply: FAILED: no configuration serial available");
                return "no configuration serial available";
            }

            foreach (var o in outs) {
                if (!o.enabled || o.current_mode == null) {
                    WLHooks.output_mgmt_config_disable(o.name);
                    DiagLog.log("apply:   %s -> off", o.name);
                } else {
                    int mhz = o.current_mode.refresh_mhz();
                    WLHooks.output_mgmt_config_enable(o.name,
                        o.current_mode.width, o.current_mode.height, mhz,
                        o.pos_x, o.pos_y, (int) o.transform);
                    DiagLog.log("apply:   %s -> on %dx%d@%d  pos=%d,%d  transform=%s",
                        o.name, o.current_mode.width, o.current_mode.height, mhz,
                        o.pos_x, o.pos_y, o.transform.to_arg());
                }
            }

            int res = WLHooks.output_mgmt_config_apply();
            switch (res) {
                case 0:
                    DiagLog.log("apply: ok");
                    return null;
                case 2:
                    DiagLog.log("apply: FAILED: cancelled");
                    return "configuration was cancelled (outputs changed — reopen and retry)";
                default:
                    DiagLog.log("apply: FAILED: compositor rejected the configuration");
                    return "the compositor rejected the configuration";
            }
        }
    }
}
