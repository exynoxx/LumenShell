using Gee;
using GLib;

namespace LumenSettings {

    /* Section-aware INI store that preserves comments, blank lines, and the
     * relative order of lines that were already in the file. New keys are
     * appended to their section (creating the section if needed) just before
     * the next section header or at end of file. */
    public class IniStore : GLib.Object {
        public string path { get; construct; }

        class Line : GLib.Object {
            public string kind;       // "section" | "kv" | "raw"
            public string section;
            public string key;
            public string value;
            public string raw;        // verbatim raw for "raw"; rebuilt for kv/section
        }

        Gee.ArrayList<Line> lines = new Gee.ArrayList<Line>();

        public IniStore(string path) {
            Object(path: path);
            load();
        }

        public string? get_value(string section, string key) {
            foreach (var l in lines) {
                if (l.kind == "kv" && l.section == section && l.key == key) return l.value;
            }
            return null;
        }

        public Gee.ArrayList<string> sections() {
            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<string>();
            foreach (var l in lines) {
                if (l.kind == "section" && !seen.contains(l.section)) {
                    seen.add(l.section);
                    ordered.add(l.section);
                }
            }
            return ordered;
        }

        public Gee.ArrayList<string> keys_in(string section) {
            var ks = new Gee.ArrayList<string>();
            foreach (var l in lines) {
                if (l.kind == "kv" && l.section == section) ks.add(l.key);
            }
            return ks;
        }

        public void set_value(string section, string key, string value) {
            for (int i = 0; i < lines.size; i++) {
                var l = lines.get(i);
                if (l.kind == "kv" && l.section == section && l.key == key) {
                    l.value = value;
                    l.raw   = "%s = %s".printf(key, value);
                    return;
                }
            }

            // Find insertion point: last line that still belongs to <section>
            // (kv or raw inside section). If section header doesn't exist,
            // append a new one at EOF first.
            int section_start = -1;
            int insert_after  = -1;
            for (int i = 0; i < lines.size; i++) {
                var l = lines.get(i);
                if (l.kind == "section" && l.section == section) {
                    section_start = i;
                    insert_after = i;
                    continue;
                }
                if (section_start >= 0 && l.kind == "section" && l.section != section) {
                    break;
                }
                if (section_start >= 0) insert_after = i;
            }

            if (section_start < 0) {
                if (lines.size > 0 && lines.get(lines.size - 1).raw != "") {
                    lines.add(make_raw(""));
                }
                lines.add(make_section(section));
                lines.add(make_kv(section, key, value));
            } else {
                lines.insert(insert_after + 1, make_kv(section, key, value));
            }
        }

        public void remove_key(string section, string key) {
            for (int i = 0; i < lines.size; i++) {
                var l = lines.get(i);
                if (l.kind == "kv" && l.section == section && l.key == key) {
                    lines.remove_at(i);
                    return;
                }
            }
        }

        public void save() {
            var parent = Path.get_dirname(path);
            try { DirUtils.create_with_parents(parent, 0755); }
            catch (Error e) { stderr.printf("IniStore: mkdir: %s\n", e.message); return; }

            var sb = new StringBuilder();
            foreach (var l in lines) {
                sb.append(l.raw);
                sb.append("\n");
            }
            try {
                FileUtils.set_contents(path, sb.str);
            } catch (Error e) {
                stderr.printf("IniStore: write %s: %s\n", path, e.message);
            }
        }

        void load() {
            lines.clear();
            if (!FileUtils.test(path, FileTest.EXISTS)) return;

            string content;
            try {
                FileUtils.get_contents(path, out content);
            } catch (Error e) {
                stderr.printf("IniStore: read %s: %s\n", path, e.message);
                return;
            }

            string section = "";
            foreach (var raw in content.split("\n")) {
                var stripped = raw.strip();
                if (stripped == "" || stripped.has_prefix("#") || stripped.has_prefix(";")) {
                    lines.add(make_raw(raw));
                    continue;
                }
                if (stripped.has_prefix("[") && stripped.has_suffix("]")) {
                    section = stripped.substring(1, stripped.length - 2).strip();
                    var line = new Line();
                    line.kind = "section"; line.section = section; line.raw = raw;
                    line.key = ""; line.value = "";
                    lines.add(line);
                    continue;
                }
                int eq = stripped.index_of_char('=');
                if (eq < 0) {
                    lines.add(make_raw(raw));
                    continue;
                }
                string k = stripped.substring(0, eq).strip();
                string v = stripped.substring(eq + 1).strip();
                var kv = new Line();
                kv.kind = "kv"; kv.section = section; kv.key = k; kv.value = v; kv.raw = raw;
                lines.add(kv);
            }
        }

        Line make_section(string s) {
            var l = new Line();
            l.kind = "section"; l.section = s; l.key = ""; l.value = ""; l.raw = "[" + s + "]";
            return l;
        }
        Line make_kv(string s, string k, string v) {
            var l = new Line();
            l.kind = "kv"; l.section = s; l.key = k; l.value = v; l.raw = "%s = %s".printf(k, v);
            return l;
        }
        Line make_raw(string r) {
            var l = new Line();
            l.kind = "raw"; l.section = ""; l.key = ""; l.value = ""; l.raw = r;
            return l;
        }
    }
}
