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
            var sl = new Gtk.StringList(labels);
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
