namespace LumenSettings {

    // Thin wrapper over Adw.ActionRow. Keeps the historical `row_title` /
    // `row_subtitle` / `set_suffix()` API so the page code (and the
    // Switch/Spin/Entry/Color/File/Binding rows that subclass this) is
    // unchanged, while the actual rendering, spacing and theming come from
    // libadwaita.
    public class ActionRow : Adw.ActionRow {
        Gtk.Widget? current_suffix = null;

        public string row_title {
            owned get { return title; }
            set { title = value; }
        }
        public string row_subtitle {
            owned get { return subtitle; }
            set { subtitle = value ?? ""; }
        }

        public ActionRow(string title, string subtitle = "") {
            // Plain labels, not markup: avoids an `&`/`<` in a title being
            // misread as Pango markup.
            use_markup = false;
            this.title = title;
            this.subtitle = subtitle ?? "";
        }

        // Replace whatever sits in the suffix area with `w`. Mirrors the old
        // single-slot behaviour the subclasses rely on.
        public void set_suffix(Gtk.Widget w) {
            if (current_suffix != null) {
                remove(current_suffix);
            }
            w.valign = Gtk.Align.CENTER;
            add_suffix(w);
            current_suffix = w;
        }
    }
}
