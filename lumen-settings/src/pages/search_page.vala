using LumenCommon;

namespace LumenSettings {

    public class SearchPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "search"; } }
        public string title     { owned get { return "Search"; } }
        public string icon_name { owned get { return "system-search-symbolic"; } }

        // One store shared by the rows and the boost-dirs list, so each save keeps the other's keys.
        JsonStore store;
        JsonRows rows;
        Adw.PreferencesGroup folders;
        Gtk.Widget[] folder_rows = {};

        public Gtk.Widget build() {
            store = new JsonStore(Paths.search_json());
            rows = new JsonRows(store);

            var page = new Adw.PreferencesPage();

            var behavior = new Adw.PreferencesGroup() { title = "Behavior" };
            behavior.add(rows.bool_row("search.content", "Search file contents", true,
                "also match text inside indexed files"));
            page.add(behavior);

            folders = new Adw.PreferencesGroup() {
                title = "Boosted folders",
                description = "Results in these folders rank higher (Documents, Desktop, Downloads, Pictures, Music and Videos always do)",
            };
            var add = new Adw.ButtonRow() { title = "Add folder…", start_icon_name = "list-add-symbolic" };
            add.activated.connect(pick_folder);
            folders.add(add);
            rebuild_folders();
            page.add(folders);

            var look = new Adw.PreferencesGroup() { title = "Appearance" };
            look.add(rows.int_row("search.width", "Width", 300, 2000, 10, 680, "px"));
            look.add(rows.color_row("search.background", "Background", "#2a2a2aee", "window background"));
            look.add(rows.color_row("search.text",       "Text",       "#ffffff",   "result names and the query"));
            look.add(rows.color_row("search.muted-text", "Muted text", "#ffffff99", "folders, snippets and section titles"));
            look.add(rows.color_row("search.highlight",  "Highlight",  "#4c9bffff", "selected result and matched characters"));
            page.add(look);

            return page;
        }

        void rebuild_folders() {
            foreach (var r in folder_rows) folders.remove(r);
            folder_rows = {};
            foreach (var dir in store.get_string_array("search.boost-dirs")) {
                var row = new Adw.ActionRow() { title = dir, use_markup = false };
                var rm = new Gtk.Button.from_icon_name("user-trash-symbolic") {
                    valign = Gtk.Align.CENTER, tooltip_text = "Remove",
                };
                rm.add_css_class("flat");
                rm.clicked.connect(() => remove_folder(dir));
                row.add_suffix(rm);
                folders.add(row);
                folder_rows += row;
            }
        }

        void write_folders(string[] dirs) {
            store.set_string_array("search.boost-dirs", dirs);
            store.save();
            rebuild_folders();
        }

        void remove_folder(string dir) {
            string[] keep = {};
            foreach (var d in store.get_string_array("search.boost-dirs")) {
                if (d != dir) keep += d;
            }
            write_folders(keep);
        }

        void pick_folder() {
            var dlg = new Gtk.FileDialog() { title = "Choose a folder", modal = true };
            dlg.select_folder.begin((Gtk.Window) folders.get_root(), null, (obj, res) => {
                try {
                    var p = dlg.select_folder.end(res).get_path();
                    if (p == null) return;
                    var dirs = store.get_string_array("search.boost-dirs");
                    foreach (var d in dirs) if (d == p) return;
                    dirs += p;
                    write_folders(dirs);
                } catch (Error e) { /* cancelled */ }
            });
        }

        // Config is read once at startup by the resident daemon.
        public override string? restart_target() { return "lumen-search"; }
    }
}
