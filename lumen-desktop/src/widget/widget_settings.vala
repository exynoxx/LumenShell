// Values are stored as strings and coerced on read, so true and "true" both work.

namespace LumenDesktop {

    public class WidgetSettings : GLib.Object {

        private GLib.HashTable<string, string> values
            = new GLib.HashTable<string, string>(str_hash, str_equal);

        public void put(string key, string value) {
            values.insert(key, value);
        }

        public GLib.List<weak string> keys() {
            return values.get_keys();
        }

        public string get_raw(string key) {
            var v = values.lookup(key);
            return v ?? "";
        }

        public string get_string(string key, string fallback) {
            var v = values.lookup(key);
            return (v == null || v == "") ? fallback : v;
        }

        // Expands a leading ~ and any $VAR / ${VAR}.
        public string get_path(string key, string fallback) {
            return expand_path(get_string(key, fallback));
        }

        public bool get_bool(string key, bool fallback) {
            var v = values.lookup(key);
            if (v == null) return fallback;
            switch (v.strip().down()) {
                case "1": case "true":  case "yes": case "on":  return true;
                case "0": case "false": case "no":  case "off": return false;
                default: return fallback;
            }
        }

        public static string expand_path(string raw) {
            var p = raw.strip();
            if (p == "" || p == "~") return GLib.Environment.get_home_dir();
            if (p.has_prefix("~/")) {
                return GLib.Path.build_filename(
                    GLib.Environment.get_home_dir(), p.substring(2));
            }
            if (p.index_of_char('$') >= 0) {
                var expanded = expand_vars(p);
                if (expanded.has_prefix("~/")) {
                    return GLib.Path.build_filename(
                        GLib.Environment.get_home_dir(), expanded.substring(2));
                }
                return expanded;
            }
            return p;
        }

        // Unset variables expand to "", as in a shell.
        private static string expand_vars(string raw) {
            var sb = new GLib.StringBuilder();
            int i = 0;
            int n = raw.length;
            while (i < n) {
                if (raw[i] != '$') {
                    sb.append_c(raw[i]);
                    i++;
                    continue;
                }
                i++;
                if (i >= n) { sb.append_c('$'); break; }
                bool braced = raw[i] == '{';
                if (braced) i++;
                var name = new GLib.StringBuilder();
                while (i < n && (raw[i].isalnum() || raw[i] == '_')) {
                    name.append_c(raw[i]);
                    i++;
                }
                if (braced && i < n && raw[i] == '}') i++;
                if (name.len == 0) { sb.append_c('$'); continue; }
                var val = GLib.Environment.get_variable(name.str);
                if (val != null) sb.append(val);
            }
            return sb.str;
        }
    }
}
