using Gtk;
using Gee;

namespace LumenSettings.Wayfire {

    /* Fallback editor for a wayfire.ini section that has no plugin metadata
     * (e.g. third-party plugins or per-output sections like [output:eDP-1]).
     * Every key already in the section is shown as a free-form key = value
     * row, and new keys can be added. This guarantees that *every* section in
     * wayfire.ini is editable, not just the ones we ship metadata for. */
    public class GenericSectionPage : GLib.Object, SettingsPage {
        string section;
        IniStore store;
        string _id;
        BoxedList? list;

        public string id        { owned get { return _id; } }
        public string title     { owned get { return section; } }
        public string icon_name { owned get { return "preferences-other-symbolic"; } }

        public GenericSectionPage(string section, IniStore store) {
            this.section = section;
            this.store = store;
            this._id = "wayfire-" + section;
        }

        public Gtk.Widget build() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var lbl = new Gtk.Label(
                "Raw settings for the [%s] section. No plugin metadata is "
                .printf(section)
                + "installed for this section, so values are edited as text.") {
                xalign = 0, wrap = true,
            };
            box.append(lbl);

            list = new BoxedList("Settings");
            foreach (var key in store.keys_in(section)) {
                list.add_row(make_kv_row(key));
            }
            box.append(list);

            box.append(build_add_row());
            return box;
        }

        Gtk.Widget make_kv_row(string key) {
            var ar = new ActionRow(key, "");

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

            var suffix = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            suffix.append(entry);
            suffix.append(del);
            ar.set_suffix(suffix);
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
                list.add_row(make_kv_row(key));
                key_entry.text = "";
                val_entry.text = "";
            });

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 6,
            };
            row.append(key_entry);
            row.append(val_entry);
            row.append(add);
            return row;
        }
    }
}
