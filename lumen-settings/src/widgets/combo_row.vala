namespace LumenSettings {

    // A real Adw.ComboRow (not sealed). Adw renders a Gtk.StringList model
    // natively, so we drop the hand-wired Gtk.DropDown suffix entirely.
    public class ComboRow : Adw.ComboRow {
        string[] values;
        // Guards programmatic model rebuilds (repopulate) so the resulting
        // `selected` change does not fire value_changed and write a stray value.
        bool updating = false;
        public signal void value_changed(string val);

        public ComboRow(string title, string[] labels, string[] values,
                        string? initial_value = null, string subtitle = "",
                        bool searchable = false) {
            use_markup = false;
            this.title = title;
            this.subtitle = subtitle ?? "";
            this.values = values;

            // Build by append rather than `new Gtk.StringList(labels)`: that
            // constructor expects a NULL-terminated array, but a dynamically
            // built `string[]` (e.g. Gee `to_array()`) is not terminated and
            // GTK walks off the end. Appending uses the array length safely.
            var sl = new Gtk.StringList(null);
            foreach (var l in labels) sl.append(l);
            model = sl;

            if (searchable) {
                enable_search = true;
                // Tell the search box how to stringify each item (a
                // Gtk.StringObject) so type-to-filter works.
                expression = new Gtk.PropertyExpression(
                    typeof(Gtk.StringObject), null, "string");
            }

            selected = index_of(initial_value);

            notify["selected"].connect(() => {
                if (updating) return;
                if (selected < this.values.length) value_changed(this.values[selected]);
            });
        }

        // Swap the dropdown's contents (used by dependent dropdowns, e.g. the
        // keyboard variant list when the layout changes). Guarded so the reset
        // selection does not emit value_changed.
        public void repopulate(string[] labels, string[] values, string? selected_value) {
            updating = true;
            this.values = values;
            var sl = (Gtk.StringList) model;
            uint n = sl.get_n_items();
            if (n > 0) sl.splice(0, n, null);
            foreach (var l in labels) sl.append(l);
            selected = index_of(selected_value);
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
