namespace LumenSettings {

    public class ComboRow : Adw.ComboRow {
        string[] values;
        // Set during repopulate() so the reset selection doesn't emit value_changed.
        bool updating = false;
        public signal void value_changed(string val);

        public ComboRow(string title, string[] labels, string[] values,
                        string? initial_value = null, string subtitle = "") {
            use_markup = false;
            this.title = title;
            this.subtitle = subtitle ?? "";
            this.values = values;

            // Not `new Gtk.StringList(labels)`: it expects NULL termination,
            // which a dynamically built string[] lacks, so GTK reads past the end.
            var sl = new Gtk.StringList(null);
            foreach (var l in labels) sl.append(l);
            model = sl;

            selected = index_of(initial_value);

            notify["selected"].connect(() => {
                if (updating) return;
                if (selected < this.values.length) value_changed(this.values[selected]);
            });
        }

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
