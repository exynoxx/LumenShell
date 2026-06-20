namespace LumenSettings {

    // A real Adw.ComboRow (not sealed). Adw renders a Gtk.StringList model
    // natively, so we drop the hand-wired Gtk.DropDown suffix entirely.
    public class ComboRow : Adw.ComboRow {
        string[] values;
        public signal void value_changed(string val);

        public ComboRow(string title, string[] labels, string[] values,
                        string? initial_value = null, string subtitle = "") {
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

            uint pick = 0;
            if (initial_value != null) {
                for (uint i = 0; i < values.length; i++) {
                    if (values[i] == initial_value) { pick = i; break; }
                }
            }
            selected = pick;

            notify["selected"].connect(() => {
                if (selected < this.values.length) value_changed(this.values[selected]);
            });
        }
    }
}
