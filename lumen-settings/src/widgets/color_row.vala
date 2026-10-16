namespace LumenSettings {

    /* Emits value_changed with #rrggbbaa. */
    public class ColorRow : Adw.ActionRow {
        Gtk.ColorDialogButton button;
        // Suppresses value_changed while set_color_hex() writes the swatch.
        bool syncing = false;

        public signal void value_changed(string hex);

        public ColorRow(string title, string initial_hex, string subtitle = "") {
            Object(title: title, subtitle: subtitle, use_markup: false);

            button = new Gtk.ColorDialogButton(new Gtk.ColorDialog() {
                title = title,
                with_alpha = true,
            });
            button.rgba = parse_or_white(initial_hex);
            // Use get_rgba(): the vapi's `rgba` property compiles to an
            // out-param call that doesn't match the C getter.
            button.notify["rgba"].connect(() => {
                var picked = button.get_rgba();
                if (!syncing && picked != null) value_changed(to_hex(picked));
            });
            button.valign = Gtk.Align.CENTER;
            add_suffix(button);
        }

        public void set_color_hex(string hex) {
            syncing = true;
            button.rgba = parse_or_white(hex);
            syncing = false;
        }

        public static Gdk.RGBA parse_or_white(string s) {
            var c = Gdk.RGBA();
            if (!c.parse(s)) {
                c.red = 1; c.green = 1; c.blue = 1; c.alpha = 1;
            }
            return c;
        }

        public static string to_hex(Gdk.RGBA c) {
            return "#%02X%02X%02X%02X".printf(
                (uint) (c.red   * 255 + 0.5),
                (uint) (c.green * 255 + 0.5),
                (uint) (c.blue  * 255 + 0.5),
                (uint) (c.alpha * 255 + 0.5));
        }
    }
}
