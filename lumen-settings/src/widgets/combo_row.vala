using Gtk;

namespace LumenSettings {

    public class ComboRow : ActionRow {
        public Gtk.DropDown drop { get; private set; }
        string[] values;
        public signal void value_changed(string val);

        public ComboRow(string title, string[] labels, string[] values,
                        string? initial_value = null, string subtitle = "") {
            base(title, subtitle);
            this.values = values;
            // Build by append rather than `new Gtk.StringList(labels)`: that
            // constructor expects a NULL-terminated array, but a dynamically
            // built `string[]` (e.g. Gee `to_array()`) is not terminated and
            // GTK walks off the end. Appending uses the array length safely.
            var sl = new Gtk.StringList(null);
            foreach (var l in labels) sl.append(l);
            drop = new Gtk.DropDown(sl, null);

            uint pick = 0;
            if (initial_value != null) {
                for (uint i = 0; i < values.length; i++) {
                    if (values[i] == initial_value) { pick = i; break; }
                }
            }
            drop.set_selected(pick);

            drop.notify["selected"].connect(() => {
                uint i = drop.get_selected();
                if (i < this.values.length) value_changed(this.values[i]);
            });

            set_suffix(drop);
        }
    }
}
