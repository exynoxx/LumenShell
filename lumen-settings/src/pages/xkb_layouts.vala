using Gee;

namespace LumenSettings {

    /* Parses the X11 xkb rules listing (`evdev.lst`) into the layout and
     * per-layout variant tables the Keyboard page's dropdowns need.
     *
     * The file is sectioned by `! <section>` headers; we only care about
     * `! layout` and `! variant`:
     *
     *   ! layout
     *     us              English (US)
     *     de              German
     *   ! variant
     *     dvorak          us: English (Dvorak)
     *     nodeadkeys      de: German (no dead keys)
     *
     * Layout lines are `<code> <name>`; variant lines are
     * `<varcode> <layoutcode>: <name>` — grouped here by <layoutcode>.
     *
     * Fail-soft: if the file is missing/unreadable, fall back to a small
     * hard-coded layout list and no variants. */
    public class XkbLayouts : GLib.Object {
        const string PATH = "/usr/share/X11/xkb/rules/evdev.lst";

        public string[] layout_codes;
        public string[] layout_names;

        // layout code -> parallel variant code/name lists (each prefixed with
        // the synthetic ("", "Default") entry).
        Gee.HashMap<string, Gee.ArrayList<string>> var_codes
            = new Gee.HashMap<string, Gee.ArrayList<string>>();
        Gee.HashMap<string, Gee.ArrayList<string>> var_names
            = new Gee.HashMap<string, Gee.ArrayList<string>>();

        public class VariantList : GLib.Object {
            public string[] codes;
            public string[] names;
        }

        public XkbLayouts() {
            load();
        }

        public VariantList variants_for(string layout) {
            var vl = new VariantList();
            var codes = new Gee.ArrayList<string>();
            var names = new Gee.ArrayList<string>();
            // Default (no variant) always first.
            codes.add("");
            names.add("Default");
            if (var_codes.has_key(layout)) {
                foreach (var c in var_codes.get(layout)) codes.add(c);
                foreach (var n in var_names.get(layout)) names.add(n);
            }
            vl.codes = codes.to_array();
            vl.names = names.to_array();
            return vl;
        }

        void load() {
            string content;
            if (!FileUtils.test(PATH, FileTest.EXISTS)) {
                load_fallback();
                return;
            }
            try {
                FileUtils.get_contents(PATH, out content);
            } catch (Error e) {
                stderr.printf("XkbLayouts: read %s: %s\n", PATH, e.message);
                load_fallback();
                return;
            }

            var lcodes = new Gee.ArrayList<string>();
            var lnames = new Gee.ArrayList<string>();

            string mode = "";
            foreach (var raw in content.split("\n")) {
                var line = raw.chomp();
                var stripped = line.strip();
                if (stripped == "") continue;
                if (stripped.has_prefix("!")) {
                    mode = stripped.substring(1).strip();
                    continue;
                }

                if (mode == "layout") {
                    string code, name;
                    split_code_rest(stripped, out code, out name);
                    if (code == "") continue;
                    lcodes.add(code);
                    lnames.add(name == "" ? code : name);
                } else if (mode == "variant") {
                    string vcode, rest;
                    split_code_rest(stripped, out vcode, out rest);
                    int colon = rest.index_of(":");
                    if (vcode == "" || colon < 0) continue;
                    string layout = rest.substring(0, colon).strip();
                    string vname = rest.substring(colon + 1).strip();
                    if (layout == "") continue;
                    if (!var_codes.has_key(layout)) {
                        var_codes.set(layout, new Gee.ArrayList<string>());
                        var_names.set(layout, new Gee.ArrayList<string>());
                    }
                    var_codes.get(layout).add(vcode);
                    var_names.get(layout).add(vname == "" ? vcode : vname);
                }
            }

            if (lcodes.size == 0) {
                load_fallback();
                return;
            }
            layout_codes = lcodes.to_array();
            layout_names = lnames.to_array();
        }

        // Split a line into its first whitespace-delimited token and the
        // remainder (trimmed). Tabs and spaces both separate.
        static void split_code_rest(string line, out string code, out string rest) {
            var s = line.strip();
            int i = 0;
            while (i < s.length && s[i] != ' ' && s[i] != '\t') i++;
            code = s.substring(0, i);
            rest = (i < s.length) ? s.substring(i).strip() : "";
        }

        void load_fallback() {
            layout_codes = { "us", "gb", "de", "fr", "dk", "es", "it", "se", "no" };
            layout_names = {
                "English (US)", "English (UK)", "German", "French", "Danish",
                "Spanish", "Italian", "Swedish", "Norwegian"
            };
            var_codes.clear();
            var_names.clear();
        }
    }
}
