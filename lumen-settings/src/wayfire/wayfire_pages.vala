using Gtk;
using Gee;

namespace LumenSettings.Wayfire {

    public class WayfirePages {
        const string METADATA_DIR = "/usr/share/wayfire/metadata";
        const string[] CURATED = {
            "core", "alpha", "animate", "decoration", "pixdecor",
            "blur", "command", "input", "expo", "scale", "grid"
        };

        public static void register(PageRegistry r) {
            var store = new IniStore(Paths.wayfire_ini());
            var plugins = Metadata.load_dir(METADATA_DIR);

            r.add(new WayfirePluginsPage(plugins, store), "Wayfire");

            var by_name = new Gee.HashMap<string, PluginDef>();
            foreach (var p in plugins) by_name.set(p.name, p);

            foreach (var name in CURATED) {
                if (!by_name.has_key(name)) continue;
                r.add(new PluginPage(by_name.get(name), store), "Wayfire");
            }
        }
    }

    public class WayfirePluginsPage : GLib.Object, SettingsPage {
        Gee.ArrayList<PluginDef> plugins;
        IniStore store;

        public string id        { owned get { return "wayfire-plugins"; } }
        public string title     { owned get { return "Wayfire Plugins"; } }
        public string icon_name { owned get { return "preferences-system-symbolic"; } }

        public WayfirePluginsPage(Gee.ArrayList<PluginDef> plugins, IniStore store) {
            this.plugins = plugins;
            this.store = store;
        }

        public Gtk.Widget build() {
            var scroll = new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                hexpand = true, vexpand = true,
            };
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var list = new BoxedList("Enabled plugins");
            foreach (var p in plugins) {
                var enabled = is_enabled(p.name);
                var row = new SwitchRow(p.short_label, p.name, enabled);
                row.toggled.connect((v) => {
                    set_enabled(p.name, v);
                });
                list.add_row(row);
            }
            box.append(list);

            scroll.set_child(box);
            return scroll;
        }

        bool is_enabled(string name) {
            var raw = store.get_value("core", "plugins") ?? "";
            foreach (var tok in raw.split(" ")) {
                if (tok.strip() == name) return true;
            }
            return false;
        }

        void set_enabled(string name, bool on) {
            var raw = store.get_value("core", "plugins") ?? "";
            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<string>();
            foreach (var tok in raw.split(" ")) {
                var t = tok.strip();
                if (t == "") continue;
                if (!seen.contains(t)) { seen.add(t); ordered.add(t); }
            }
            if (on) {
                if (!seen.contains(name)) ordered.add(name);
            } else {
                ordered.remove(name);
            }
            var sb = new StringBuilder();
            for (int i = 0; i < ordered.size; i++) {
                if (i > 0) sb.append(" ");
                sb.append(ordered.get(i));
            }
            store.set_value("core", "plugins", sb.str);
            store.save();
        }
    }
}
