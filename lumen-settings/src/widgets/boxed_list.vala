namespace LumenSettings {

    // Adw.PreferencesGroup is the native boxed-list container: it draws the
    // rounded card, the row separators and the optional group title. `add_row`
    // is kept as an alias of Adw's `add()` so page code is unchanged.
    public class BoxedList : Adw.PreferencesGroup {
        public BoxedList(string? group_title = null) {
            if (group_title != null && group_title != "") {
                // Adw.PreferencesGroup renders its title as Pango markup and
                // has no use-markup toggle, so a literal '&'/'<' (e.g.
                // "Suspend & lock") must be escaped.
                title = Markup.escape_text(group_title);
            }
        }

        public void add_row(Gtk.Widget row) {
            add(row);
        }
    }
}
