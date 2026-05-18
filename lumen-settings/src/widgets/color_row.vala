using Gtk;

namespace LumenSettings {

    /* Trailing button is a colored swatch; clicking it opens Gtk.ColorDialog
     * (GTK4 modern API). Emits value_changed with #rrggbbaa. */
    public class ColorRow : ActionRow {
        Gtk.Button button;
        Gdk.RGBA current;
        public signal void value_changed(string hex);

        public ColorRow(string title, string initial_hex, string subtitle = "") {
            base(title, subtitle);
            current = parse_or_white(initial_hex);

            button = new Gtk.Button();
            button.add_css_class("lumen-color-swatch");
            apply_swatch();
            button.clicked.connect(open_picker);
            set_suffix(button);
        }

        public void set_color_hex(string hex) {
            current = parse_or_white(hex);
            apply_swatch();
        }

        void apply_swatch() {
            var provider = new Gtk.CssProvider();
            provider.load_from_string(".lumen-color-swatch.this { background: %s; }"
                .printf(current.to_string()));
            button.get_style_context().add_provider(
                provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            button.add_css_class("this");
        }

        void open_picker() {
            var dlg = new Gtk.ColorDialog() {
                title = row_title,
                with_alpha = true,
            };
            dlg.choose_rgba.begin(
                (Gtk.Window) get_root(),
                current,
                null,
                (obj, res) => {
                    try {
                        var picked = dlg.choose_rgba.end(res);
                        if (picked != null) {
                            current = picked;
                            apply_swatch();
                            value_changed(to_hex(current));
                        }
                    } catch (Error e) {
                        // Cancellation lands here too — ignore.
                    }
                }
            );
        }

        static Gdk.RGBA parse_or_white(string s) {
            var c = Gdk.RGBA();
            if (!c.parse(s)) {
                c.red = 1; c.green = 1; c.blue = 1; c.alpha = 1;
            }
            return c;
        }

        static string to_hex(Gdk.RGBA c) {
            return "#%02X%02X%02X%02X".printf(
                (uint) (c.red   * 255 + 0.5),
                (uint) (c.green * 255 + 0.5),
                (uint) (c.blue  * 255 + 0.5),
                (uint) (c.alpha * 255 + 0.5));
        }
    }
}
