using Gtk;

namespace LumenSettings {

    public class EntryRow : ActionRow {
        public Gtk.Entry entry { get; private set; }
        public signal void value_changed(string val);

        public EntryRow(string title, string initial, string subtitle = "") {
            base(title, subtitle);
            entry = new Gtk.Entry() {
                text = initial,
                hexpand = false,
                width_chars = 16,
                max_width_chars = 16,
            };
            entry.changed.connect(() => value_changed(entry.text));
            set_suffix(entry);
        }
    }
}
