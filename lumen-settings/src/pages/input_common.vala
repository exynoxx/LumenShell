using Gtk;

namespace LumenSettings {

    /* Thin wrapper over the `[input]` section of ~/.config/wayfire.ini, with
     * row-builder helpers so the Keyboard/Mouse/Touchpad pages don't each
     * repeat the read-fallback / write / save boilerplate.
     *
     * Every write reloads the backing file first: all three input pages (plus
     * the Panel and Desktop pages) build their stores at startup from the SAME
     * wayfire.ini snapshot, so a stale snapshot would clobber a sibling page's
     * edits on save. reload() re-reads the file, then we re-set the single key.
     *
     * Doubles are formatted locale-independently (g_ascii_formatd) — the box
     * may run a comma-decimal locale (da_DK) and wayfire.ini must use '.'. */
    public class InputSection : GLib.Object {
        public const string SECTION = "input";
        IniStore store;

        public InputSection() {
            store = new IniStore(Paths.wayfire_ini());
        }

        public string? get_str(string key) {
            return store.get_value(SECTION, key);
        }

        public void put(string key, string value) {
            store.reload();
            store.set_value(SECTION, key, value);
            store.save();
        }

        public SwitchRow bool_row(string key, string label, bool dflt,
                                  string subtitle = "") {
            bool initial = parse_bool(store.get_value(SECTION, key), dflt);
            var row = new SwitchRow(label, subtitle, initial);
            row.toggled.connect((active) => put(key, active ? "true" : "false"));
            return row;
        }

        public SpinRow double_row(string key, string label, double min, double max,
                                  double step, double dflt, int precision,
                                  string subtitle = "") {
            double initial = parse_double(store.get_value(SECTION, key), dflt);
            var row = new SpinRow(label, min, max, step, initial, precision, subtitle);
            row.value_changed.connect((v) => put(key, fmt_double(v, precision)));
            return row;
        }

        public SpinRow int_row(string key, string label, double min, double max,
                               double step, int64 dflt, string subtitle = "") {
            int64 initial = parse_int(store.get_value(SECTION, key), dflt);
            var row = new SpinRow(label, min, max, step, (double) initial, 0, subtitle);
            row.value_changed.connect((v) => put(key, "%lld".printf((int64) v)));
            return row;
        }

        public ComboRow combo_row(string key, string label, string[] labels,
                                  string[] values, string dflt,
                                  string subtitle = "") {
            var initial = store.get_value(SECTION, key) ?? dflt;
            var row = new ComboRow(label, labels, values, initial, subtitle);
            row.value_changed.connect((v) => put(key, v));
            return row;
        }

        static bool parse_bool(string? s, bool dflt) {
            if (s == null) return dflt;
            var t = s.strip().down();
            if (t == "true" || t == "1" || t == "yes" || t == "on")  return true;
            if (t == "false" || t == "0" || t == "no" || t == "off") return false;
            return dflt;
        }

        static double parse_double(string? s, double dflt) {
            if (s == null) return dflt;
            double d;
            // double.try_parse uses g_ascii_strtod — locale-independent.
            return double.try_parse(s.strip(), out d) ? d : dflt;
        }

        static int64 parse_int(string? s, int64 dflt) {
            if (s == null) return dflt;
            int64 v;
            return int64.try_parse(s.strip(), out v) ? v : dflt;
        }

        // Locale-independent "%.<precision>f" — wayfire.ini decimals must use
        // '.' regardless of LC_NUMERIC.
        static string fmt_double(double v, int precision) {
            // double.format == g_ascii_formatd: always '.' for the decimal point.
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            string fmt = "%%.%df".printf(precision);
            string result = v.format(buf, fmt);
            return result;
        }
    }
}
