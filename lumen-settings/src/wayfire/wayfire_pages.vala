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

        Gtk.SearchBar search_bar;
        Gtk.SearchEntry search_entry;
        BoxedList plugin_list;
        BoxedList? other_list;
        Gee.ArrayList<Gtk.ListBoxRow> plugin_rows;
        Gee.ArrayList<Gtk.ListBoxRow> other_rows;
        Gee.HashMap<Gtk.ListBoxRow, string> search_text;

        public string id        { owned get { return "wayfire-plugins"; } }
        public string title     { owned get { return "Wayfire Plugins"; } }
        public string icon_name { owned get { return "preferences-system-symbolic"; } }

        // This page pins its own search bar / back button outside an inner
        // ScrolledWindow, so it must not be wrapped in the window's scroller.
        public bool scrolls_itself() { return true; }

        public WayfirePluginsPage(Gee.ArrayList<PluginDef> plugins, IniStore store) {
            this.plugins = plugins;
            this.store = store;
            this.by_name = new Gee.HashMap<string, PluginDef>();
            foreach (var p in plugins) by_name.set(p.name, p);
        }

        public Gtk.Widget build() {
            // The window already wraps this in a ScrolledWindow, so the children
            // are plain boxes (no nested scrollbars).
            stack = new Gtk.Stack() {
                transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
                hexpand = true, vexpand = true,
            };
            row_map = new Gee.HashMap<Gtk.ListBoxRow, string>();
            search_text = new Gee.HashMap<Gtk.ListBoxRow, string>();
            plugin_rows = new Gee.ArrayList<Gtk.ListBoxRow>();
            other_rows = new Gee.ArrayList<Gtk.ListBoxRow>();

            stack.add_named(build_list_view(), "list");
            stack.set_visible_child_name("list");

            // Typing anywhere in the window reveals the search bar; it stays
            // hidden while empty (Escape clears and hides it again). Key
            // capture must hang off the toplevel — not this stack — since the
            // stack rarely holds focus. We only bind it on the list view: on
            // the detail view a BindingRow needs raw key events to capture
            // shortcuts, and a toplevel capture would swallow them first.
            stack.map.connect(update_search_capture);
            stack.unmap.connect(() => search_bar.set_key_capture_widget(null));
            stack.notify["visible-child-name"].connect(update_search_capture);
            return stack;
        }

        void update_search_capture() {
            var root = stack.get_root() as Gtk.Widget;
            if (root == null) return;
            if (stack.get_mapped() && stack.visible_child_name == "list") {
                search_bar.set_key_capture_widget(root);
            } else {
                search_bar.set_key_capture_widget(null);
            }
        }

        Gtk.Widget build_list_view() {
            var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
                hexpand = true, vexpand = true,
            };

            // A revealer that stays collapsed until the user starts typing, so
            // nothing is shown while the search is empty. Pinned above the
            // scroller so it stays visible no matter how far the list scrolls.
            search_entry = new Gtk.SearchEntry() {
                placeholder_text = "Search plugins",
                hexpand = true,
            };
            search_entry.search_changed.connect(apply_filter);
            search_bar = new Gtk.SearchBar() {
                show_close_button = true,
            };
            search_bar.set_child(search_entry);
            search_bar.connect_entry(search_entry);
            outer.append(search_bar);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            plugin_list = new BoxedList("Plugins");
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
                other_list = new BoxedList("Other sections");
                foreach (var name in others) {
                    other_list.add_row(make_section_row(name));
                }
                other_list.list.row_activated.connect(on_row_activated);
                box.append(other_list);
            }

            var scroller = new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                hexpand = true, vexpand = true,
                child = box,
            };
            outer.append(scroller);
            return outer;
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
            search_text.set(ar, (p.short_label + " " + p.name).down());
            plugin_rows.add(ar);
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
            search_text.set(ar, name.down());
            other_rows.add(ar);
            return ar;
        }

        void apply_filter() {
            var q = search_entry.text.strip().down();
            filter_group(plugin_list, plugin_rows, q);
            if (other_list != null) filter_group(other_list, other_rows, q);
        }

        void filter_group(BoxedList group, Gee.ArrayList<Gtk.ListBoxRow> rows, string q) {
            int visible = 0;
            foreach (var row in rows) {
                bool match = q == "" || (search_text.get(row) ?? "").contains(q);
                row.visible = match;
                if (match) visible++;
            }
            group.visible = visible > 0;
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

            // Header (back button + title) is pinned above the scroller so it
            // stays in place while the plugin's options scroll beneath it.
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

            var scroller = new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                hexpand = true, vexpand = true,
                child = body,
            };
            box.append(scroller);
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
