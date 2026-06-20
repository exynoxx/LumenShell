using Gtk;

namespace LumenSettings {

    public class ComboRow : ActionRow {
        public Gtk.DropDown drop { get; private set; }
        Gtk.StringList model;
        string[] values;
        // Guards programmatic model rebuilds (repopulate) so the resulting
        // `selected` change does not fire value_changed and write a stray value.
        bool updating = false;
        public signal void value_changed(string val);

        public ComboRow(string title, string[] labels, string[] values,
                        string? initial_value = null, string subtitle = "",
                        bool searchable = false) {
            base(title, subtitle);
            this.values = values;
            // Build by append rather than `new Gtk.StringList(labels)`: that
            // constructor expects a NULL-terminated array, but a dynamically
            // built `string[]` (e.g. Gee `to_array()`) is not terminated and
            // GTK walks off the end. Appending uses the array length safely.
            model = new Gtk.StringList(null);
            foreach (var l in labels) model.append(l);
            drop = new Gtk.DropDown(model, null);

            if (searchable) {
                drop.enable_search = true;
                // Tell the search box how to stringify each item (a
                // Gtk.StringObject) so type-to-filter works.
                drop.expression = new Gtk.PropertyExpression(
                    typeof(Gtk.StringObject), null, "string");
            }

            drop.set_selected(index_of(initial_value));

            drop.notify["selected"].connect(() => {
                if (updating) return;
                uint i = drop.get_selected();
                if (i < this.values.length) value_changed(this.values[i]);
            });

            set_suffix(drop);
        }

        // Swap the dropdown's contents (used by dependent dropdowns, e.g. the
        // keyboard variant list when the layout changes). Guarded so the reset
        // selection does not emit value_changed.
        public void repopulate(string[] labels, string[] values, string? selected) {
            updating = true;
            this.values = values;
            uint n = model.get_n_items();
            if (n > 0) model.splice(0, n, null);
            foreach (var l in labels) model.append(l);
            drop.set_selected(index_of(selected));
            updating = false;
        }

        uint index_of(string? value) {
            if (value != null) {
                for (uint i = 0; i < values.length; i++) {
                    if (values[i] == value) return i;
                }
            }
            return 0;
        }
    }
}
