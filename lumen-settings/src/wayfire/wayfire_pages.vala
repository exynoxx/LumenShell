using Gtk;
using Gee;

namespace LumenSettings.Wayfire {

    public class WayfirePages {
        const string METADATA_DIR = "/usr/share/wayfire/metadata";

        public static void register(PageRegistry r) {
            var store = new IniStore(Paths.wayfire_ini());
            var plugins = Metadata.load_dir(METADATA_DIR);

            // A single sidebar entry. Individual plugin/section settings open
            // as an in-page detail view (with a back button), not as their own
            // sidebar entries.
            r.add(new WayfirePluginsPage(plugins, store), "Wayfire");
        }
    }

    public class WayfirePluginsPage : GLib.Object, SettingsPage {
        Gee.ArrayList<PluginDef> plugins;
        IniStore store;
        Gee.HashMap<string, PluginDef> by_name;

        Gtk.Stack stack;
        Gtk.Widget? detail_child;
        Gee.HashMap<Gtk.ListBoxRow, string> row_map;

        public string id        { owned get { return "wayfire-plugins"; } }
        public string title     { owned get { return "Wayfire Plugins"; } }
        public string icon_name { owned get { return "preferences-system-symbolic"; } }

        public WayfirePluginsPage(Gee.ArrayList<PluginDef> plugins, IniStore store) {
            this.plugins = plugins;
            this.store = store;
            this.by_name = new Gee.HashMap<string, PluginDef>();
            foreach (var p in plugins) by_name.set(p.name, p);
        }

        public Gtk.Widget build() {
            // Master-detail inside one page: a "list" view of plugins/sections
            // and a "detail" view built on demand when a row is clicked. The
            // window already wraps this in a ScrolledWindow, so the children
            // are plain boxes (no nested scrollbars).
            stack = new Gtk.Stack() {
                transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
                hexpand = true, vexpand = true,
            };
            row_map = new Gee.HashMap<Gtk.ListBoxRow, string>();

            stack.add_named(build_list_view(), "list");
            stack.set_visible_child_name("list");
            return stack;
        }

        Gtk.Widget build_list_view() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            // Documented plugins: an enable toggle plus a clickable row that
            // opens the plugin's settings.
            var plugin_list = new BoxedList("Plugins");
            foreach (var p in plugins) {
                plugin_list.add_row(make_plugin_row(p));
            }
            plugin_list.list.row_activated.connect(on_row_activated);
            box.append(plugin_list);

            // Sections present in wayfire.ini that have no metadata (e.g.
            // third-party plugins, per-output sections). Editable via the raw
            // key = value editor.
            var others = new Gee.ArrayList<string>();
            foreach (var section in store.sections()) {
                if (!by_name.has_key(section)) others.add(section);
            }
            if (others.size > 0) {
                var other_list = new BoxedList("Other sections");
                foreach (var name in others) {
                    other_list.add_row(make_section_row(name));
                }
                other_list.list.row_activated.connect(on_row_activated);
                box.append(other_list);
            }

            return box;
        }

        Gtk.ListBoxRow make_plugin_row(PluginDef p) {
            var ar = new ActionRow(p.short_label, p.name);
            ar.activatable = true;

            var sw = new Gtk.Switch() {
                valign = Gtk.Align.CENTER,
                active = is_enabled(p.name),
            };
            // The switch consumes its own clicks, so toggling enable/disable
            // does not trigger row activation (navigation).
            sw.notify["active"].connect(() => set_enabled(p.name, sw.active));

            var chevron = new Gtk.Image.from_icon_name("go-next-symbolic") {
                valign = Gtk.Align.CENTER,
            };
            chevron.add_css_class("dim-label");

            var suffix = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
            suffix.append(sw);
            suffix.append(chevron);
            ar.set_suffix(suffix);

            row_map.set(ar, p.name);
            return ar;
        }

        Gtk.ListBoxRow make_section_row(string name) {
            var ar = new ActionRow(name, "no metadata — raw editor");
            ar.activatable = true;

            var chevron = new Gtk.Image.from_icon_name("go-next-symbolic") {
                valign = Gtk.Align.CENTER,
            };
            chevron.add_css_class("dim-label");
            ar.set_suffix(chevron);

            row_map.set(ar, name);
            return ar;
        }

        void on_row_activated(Gtk.ListBoxRow row) {
            if (row_map.has_key(row)) open(row_map.get(row));
        }

        void open(string name) {
            SettingsPage page = by_name.has_key(name)
                ? (SettingsPage) new PluginPage(by_name.get(name), store)
                : (SettingsPage) new GenericSectionPage(name, store);
            show_detail(page.title, page.build());
        }

        void show_detail(string title, Gtk.Widget body) {
            if (detail_child != null) stack.remove(detail_child);
            detail_child = build_detail(title, body);
            stack.add_named(detail_child, "detail");
            stack.set_visible_child_name("detail");
        }

        Gtk.Widget build_detail(string title, Gtk.Widget body) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
                hexpand = true, vexpand = true,
            };

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
                margin_top = 18, margin_start = 18, margin_end = 18,
            };
            var back = new Gtk.Button.from_icon_name("go-previous-symbolic") {
                valign = Gtk.Align.CENTER,
                tooltip_text = "Back to plugins",
            };
            back.add_css_class("flat");
            back.clicked.connect(() => stack.set_visible_child_name("list"));
            header.append(back);

            var lbl = new Gtk.Label(title) { xalign = 0, hexpand = true };
            lbl.add_css_class("title-2");
            header.append(lbl);

            box.append(header);
            box.append(body);
            return box;
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
