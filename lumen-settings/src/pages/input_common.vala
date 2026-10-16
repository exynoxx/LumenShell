using LumenCommon;
using Gtk;

namespace LumenSettings {

    public abstract class SettingsRows : GLib.Object {

        protected abstract string? read_string(string key);
        protected abstract void    write_string(string key, string value);
        protected abstract int64   read_int(string key, int64 dflt);
        protected abstract void    write_int(string key, int64 value);
        protected abstract bool    read_bool(string key, bool dflt);
        protected abstract void    write_bool(string key, bool value);

        public Adw.SwitchRow bool_row(string key, string label, bool dflt,
                                      string subtitle = "") {
            var row = new Adw.SwitchRow() {
                title = label, subtitle = subtitle, active = read_bool(key, dflt),
            };
            row.notify["active"].connect(() => write_bool(key, row.active));
            return row;
        }

        // `scale` = stored units per displayed unit (e.g. ms shown as s).
        // `dflt` is in stored units; min/max/step in displayed units.
        public Adw.SpinRow int_row(string key, string label, double min, double max,
                                   double step, int64 dflt, string subtitle = "",
                                   int64 scale = 1) {
            var row = spin_row(label, min, max, step,
                               (double) read_int(key, dflt) / (double) scale, 0, subtitle);
            row.notify["value"].connect(() => write_int(key, (int64) (row.value * scale)));
            return row;
        }

        public ComboRow combo_row(string key, string label, string[] labels,
                                  string[] values, string dflt,
                                  string subtitle = "") {
            var row = new ComboRow(label, labels, values,
                                   read_string(key) ?? dflt, subtitle);
            row.value_changed.connect((v) => write_string(key, v));
            return row;
        }

        public ColorRow color_row(string key, string label, string dflt,
                                  string subtitle = "") {
            var row = new ColorRow(label, read_string(key) ?? dflt, subtitle);
            row.value_changed.connect((hex) => write_string(key, hex));
            return row;
        }

        public static Adw.SpinRow spin_row(string label, double min, double max,
                                           double step, double initial, uint digits,
                                           string subtitle = "") {
            return new Adw.SpinRow(new Gtk.Adjustment(initial, min, max, step, step * 10, 0),
                                   step, digits) {
                title = label, subtitle = subtitle, numeric = true,
            };
        }
    }

    // Values keep their JSON type: the runtime theme loaders are typed.
    public class JsonRows : SettingsRows {
        JsonStore store;

        public JsonRows(JsonStore store) {
            this.store = store;
        }

        protected override string? read_string(string key) {
            return store.get_string(key);
        }
        protected override void write_string(string key, string value) {
            store.set_string(key, value);
            store.save();
        }
        protected override int64 read_int(string key, int64 dflt) {
            return store.get_int(key, dflt);
        }
        protected override void write_int(string key, int64 value) {
            store.set_int(key, value);
            store.save();
        }
        protected override bool read_bool(string key, bool dflt) {
            return store.get_bool(key, dflt);
        }
        protected override void write_bool(string key, bool value) {
            store.set_bool(key, value);
            store.save();
        }
    }

    public class IniRows : SettingsRows {
        protected IniStore store;
        protected string section;

        public IniRows(string path, string section) {
            store = new IniStore(path);
            this.section = section;
        }

        public string? get_str(string key) {
            return store.get_value(section, key);
        }

        public void put(string key, string value) {
            store.reload();
            store.set_value(section, key, value);
            store.save();
        }

        public Adw.SpinRow double_row(string key, string label, double min, double max,
                                      double step, double dflt, int precision,
                                      string subtitle = "") {
            var row = spin_row(label, min, max, step, parse_double(get_str(key), dflt),
                               (uint) precision, subtitle);
            row.notify["value"].connect(() => put(key, fmt_double(row.value, precision)));
            return row;
        }

        protected override string? read_string(string key) { return get_str(key); }
        protected override void write_string(string key, string value) {
            put(key, value);
        }
        protected override int64 read_int(string key, int64 dflt) {
            var s = get_str(key);
            if (s == null) return dflt;
            int64 v;
            return int64.try_parse(s.strip(), out v) ? v : dflt;
        }
        protected override void write_int(string key, int64 value) {
            put(key, "%lld".printf(value));
        }
        protected override bool read_bool(string key, bool dflt) {
            var s = get_str(key);
            if (s == null) return dflt;
            switch (s.strip().down()) {
                case "true":  case "1": case "yes": case "on":  return true;
                case "false": case "0": case "no":  case "off": return false;
                default: return dflt;
            }
        }
        protected override void write_bool(string key, bool value) {
            put(key, value ? "true" : "false");
        }

        static double parse_double(string? s, double dflt) {
            if (s == null) return dflt;
            double d;
            // double.try_parse uses g_ascii_strtod — locale-independent.
            return double.try_parse(s.strip(), out d) ? d : dflt;
        }

        // Locale-independent: INI decimals must use '.' even under da_DK.
        static string fmt_double(double v, int precision) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format(buf, "%%.%df".printf(precision));
        }
    }

    public class InputSection : IniRows {
        public InputSection() {
            base(Paths.wayfire_ini(), "input");
        }
    }
}
