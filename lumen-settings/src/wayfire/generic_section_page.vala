namespace LumenSettings.Wayfire {

    public class GenericSectionPage : GLib.Object, SettingsPage {
        string section;
        IniStore store;
        string _id;
        Adw.PreferencesGroup? list;

        public string id        { owned get { return _id; } }
        public string title     { owned get { return section; } }
        public string icon_name { owned get { return "preferences-other-symbolic"; } }

        public GenericSectionPage(string section, IniStore store) {
            this.section = section;
            this.store = store;
            this._id = "wayfire-" + section;
        }

        public Gtk.Widget build() {
            var page = new Adw.PreferencesPage() {
                description = Markup.escape_text(
                    "Raw settings for the [%s] section. No plugin metadata is "
                    .printf(section)
                    + "installed for this section, so values are edited as text."),
            };

            list = new Adw.PreferencesGroup() { title = "Settings" };
            foreach (var key in store.keys_in(section)) {
                list.add(make_kv_row(key));
            }
            page.add(list);

            var add_group = new Adw.PreferencesGroup();
            add_group.add(build_add_row());
            page.add(add_group);
            return page;
        }

        Gtk.Widget make_kv_row(string key) {
            var ar = new Adw.ActionRow() { title = key, use_markup = false };

            var entry = new Gtk.Entry() {
                text = store.get_value(section, key) ?? "",
                hexpand = false,
                width_chars = 20,
                max_width_chars = 20,
            };
            entry.changed.connect(() => {
                store.set_value(section, key, entry.text);
                store.save();
            });

            var del = new Gtk.Button.from_icon_name("user-trash-symbolic") {
                valign = Gtk.Align.CENTER,
                tooltip_text = "Remove this setting",
            };
            del.add_css_class("flat");
            del.clicked.connect(() => {
                store.remove_key(section, key);
                store.save();
                list.remove(ar);
            });

            var suffix = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            suffix.append(entry);
            suffix.append(del);
            ar.add_suffix(suffix);
            return ar;
        }

        Gtk.Widget build_add_row() {
            var key_entry = new Gtk.Entry() {
                placeholder_text = "key",
                width_chars = 16,
            };
            var val_entry = new Gtk.Entry() {
                placeholder_text = "value",
                width_chars = 16,
                hexpand = true,
            };
            var add = new Gtk.Button.from_icon_name("list-add-symbolic") {
                valign = Gtk.Align.CENTER,
                tooltip_text = "Add setting",
            };
            add.add_css_class("flat");

            add.clicked.connect(() => {
                var key = key_entry.text.strip();
                if (key == "") return;
                if (store.get_value(section, key) != null) return;
                store.set_value(section, key, val_entry.text);
                store.save();
                list.add(make_kv_row(key));
                key_entry.text = "";
                val_entry.text = "";
            });

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            row.append(key_entry);
            row.append(val_entry);
            row.append(add);
            return row;
        }
    }
}
