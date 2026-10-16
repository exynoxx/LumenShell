using LumenCommon;
using Gtk;
using Gee;

namespace LumenSettings.Wayfire {

    public class PluginList {

        public static bool is_enabled(IniStore store, string name) {
            var raw = store.get_value("core", "plugins") ?? "";
            foreach (var tok in raw.split(" ")) {
                if (tok.strip() == name) return true;
            }
            return false;
        }

        // Order is preserved and duplicates dropped: Wayfire loads plugins in
        // list order, so reshuffling would silently change plugin precedence.
        public static void set_enabled(IniStore store, string name, bool on) {
            // Three pages each hold an IniStore on wayfire.ini; without this
            // reload a toggle writes back a stale list.
            store.reload();

            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<string>();
            foreach (var tok in (store.get_value("core", "plugins") ?? "").split(" ")) {
                var t = tok.strip();
                if (t != "" && seen.add(t)) ordered.add(t);
            }

            if (on) {
                if (!seen.contains(name)) ordered.add(name);
            } else {
                ordered.remove(name);
            }

            var sb = new StringBuilder();
            for (int i = 0; i < ordered.size; i++) {
                if (i > 0) sb.append_c(' ');
                sb.append(ordered.get(i));
            }
            store.set_value("core", "plugins", sb.str);
            store.save();
        }
    }

    public class WayfirePages {
        const string METADATA_DIR = "/usr/share/wayfire/metadata";

        public static void register(PageRegistry r) {
            var store = new IniStore(Paths.wayfire_ini());
            var plugins = Metadata.load_dir(METADATA_DIR);

            r.add(new WayfirePluginsPage(plugins, store), "Wayfire");
        }
    }

    public class WayfirePluginsPage : GLib.Object, SettingsPage {
        Gee.ArrayList<PluginDef> plugins;
        IniStore store;
        Gee.HashMap<string, PluginDef> by_name;

        Adw.NavigationView nav;
        Adw.NavigationPage list_page;
        Gee.HashMap<Gtk.ListBoxRow, string> row_map;

        Gtk.SearchBar search_bar;
        Gtk.SearchEntry search_entry;
        Adw.PreferencesGroup plugin_list;
        Adw.PreferencesGroup? other_list;
        Gee.ArrayList<Gtk.ListBoxRow> plugin_rows;
        Gee.ArrayList<Gtk.ListBoxRow> other_rows;
        Gee.HashMap<Gtk.ListBoxRow, string> search_text;

        Gee.HashMap<string, Gtk.Switch> plugin_switches;
        // Set while refresh_states() syncs switches, so it doesn't write back.
        bool suppress_toggle = false;

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
            row_map = new Gee.HashMap<Gtk.ListBoxRow, string>();
            search_text = new Gee.HashMap<Gtk.ListBoxRow, string>();
            plugin_rows = new Gee.ArrayList<Gtk.ListBoxRow>();
            other_rows = new Gee.ArrayList<Gtk.ListBoxRow>();
            plugin_switches = new Gee.HashMap<string, Gtk.Switch>();

            nav = new Adw.NavigationView();
            list_page = new Adw.NavigationPage(build_list_view(), title);
            nav.add(list_page);

            // Key capture hangs off the toplevel (this view rarely has focus),
            // and only on the list view: it would swallow BindingRow's key grabs.
            nav.map.connect(update_search_capture);
            nav.unmap.connect(() => search_bar.set_key_capture_widget(null));
            nav.notify["visible-page"].connect(update_search_capture);

            // Another page may have changed [core] plugins since this was built.
            nav.map.connect(refresh_states);
            return nav;
        }

        void refresh_states() {
            store.reload();
            suppress_toggle = true;
            foreach (var e in plugin_switches.entries) {
                bool en = is_enabled(e.key);
                if (e.value.active != en) e.value.active = en;
            }
            suppress_toggle = false;
        }

        void update_search_capture() {
            var root = nav.get_root() as Gtk.Widget;
            if (root == null) return;
            if (nav.get_mapped() && nav.visible_page == list_page) {
                search_bar.set_key_capture_widget(root);
            } else {
                search_bar.set_key_capture_widget(null);
            }
        }

        Gtk.Widget build_list_view() {
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

            var page = new Adw.PreferencesPage();

            plugin_list = new Adw.PreferencesGroup() { title = "Plugins" };
            foreach (var p in plugins) {
                plugin_list.add(make_plugin_row(p));
            }
            page.add(plugin_list);

            var others = new Gee.ArrayList<string>();
            foreach (var section in store.sections()) {
                if (!by_name.has_key(section)) others.add(section);
            }
            if (others.size > 0) {
                other_list = new Adw.PreferencesGroup() { title = "Other sections" };
                foreach (var name in others) {
                    other_list.add(make_section_row(name));
                }
                page.add(other_list);
            }

            var view = new Adw.ToolbarView() { content = page };
            view.add_top_bar(search_bar);
            return view;
        }

        Gtk.ListBoxRow make_plugin_row(PluginDef p) {
            var ar = new Adw.ActionRow() {
                title = p.short_label, subtitle = p.name, use_markup = false,
            };
            ar.activatable = true;
            ar.activated.connect(() => on_row_activated(ar));

            var sw = new Gtk.Switch() {
                valign = Gtk.Align.CENTER,
                active = is_enabled(p.name),
            };
            // The switch consumes its own clicks, so toggling doesn't navigate.
            sw.notify["active"].connect(() => {
                if (suppress_toggle) return;
                set_enabled(p.name, sw.active);
            });
            plugin_switches.set(p.name, sw);

            var chevron = new Gtk.Image.from_icon_name("go-next-symbolic") {
                valign = Gtk.Align.CENTER,
            };
            chevron.add_css_class("dim-label");

            ar.add_suffix(sw);
            ar.add_suffix(chevron);

            row_map.set(ar, p.name);
            search_text.set(ar, (p.short_label + " " + p.name).down());
            plugin_rows.add(ar);
            return ar;
        }

        Gtk.ListBoxRow make_section_row(string name) {
            var ar = new Adw.ActionRow() {
                title = name, subtitle = "no metadata — raw editor", use_markup = false,
            };
            ar.activatable = true;
            ar.activated.connect(() => on_row_activated(ar));

            var chevron = new Gtk.Image.from_icon_name("go-next-symbolic") {
                valign = Gtk.Align.CENTER,
            };
            chevron.add_css_class("dim-label");
            ar.add_suffix(chevron);

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

        void filter_group(Adw.PreferencesGroup group, Gee.ArrayList<Gtk.ListBoxRow> rows, string q) {
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
            // The header gives the detail its back button and title.
            var view = new Adw.ToolbarView() { content = page.build() };
            view.add_top_bar(new Adw.HeaderBar() {
                show_start_title_buttons = false,
                show_end_title_buttons = false,
            });
            nav.push(new Adw.NavigationPage(view, page.title));
        }

        bool is_enabled(string name) {
            return PluginList.is_enabled(store, name);
        }

        void set_enabled(string name, bool on) {
            PluginList.set_enabled(store, name, on);
        }
    }
}
