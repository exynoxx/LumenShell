using Gtk;
using Gdk;

namespace LumenSettings {

    public class BindingRow : ActionRow {
        public signal void value_changed(string binding);

        Gtk.Button button;
        string current;
        bool grabbing = false;
        Gtk.EventControllerKey key_ctl;

        public BindingRow(string title, string initial, string subtitle = "") {
            base(title, subtitle);
            current = initial;

            button = new Gtk.Button.with_label(display_for(current));
            button.add_css_class("lumen-binding-button");
            button.clicked.connect(start_grab);
            set_suffix(button);

            key_ctl = new Gtk.EventControllerKey();
            key_ctl.key_pressed.connect(on_key_pressed);
            button.add_controller(key_ctl);

            var rclick = new Gtk.GestureClick() { button = Gdk.BUTTON_SECONDARY };
            rclick.pressed.connect((n, x, y) => {
                current = "";
                button.label = display_for(current);
                value_changed(current);
            });
            button.add_controller(rclick);
        }

        public void set_binding(string s) {
            current = s;
            button.label = display_for(current);
        }

        void start_grab() {
            grabbing = true;
            button.label = "Press a key...";
            button.grab_focus();
        }

        bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
            if (!grabbing) return false;
            if (keyval == Gdk.Key.Escape) {
                grabbing = false;
                button.label = display_for(current);
                return true;
            }
            if (is_modifier_only(keyval)) return true;

            var sb = new StringBuilder();
            if ((state & Gdk.ModifierType.SHIFT_MASK)   != 0) sb.append("<shift> ");
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) sb.append("<ctrl> ");
            if ((state & Gdk.ModifierType.ALT_MASK)     != 0) sb.append("<alt> ");
            if ((state & Gdk.ModifierType.SUPER_MASK)   != 0) sb.append("<super> ");
            if ((state & Gdk.ModifierType.META_MASK)    != 0) sb.append("<meta> ");

            string? name = Gdk.keyval_name(keyval);
            if (name == null || name == "") name = "Unknown";
            string token = name.up();
            if (!token.has_prefix("KEY_") && !token.has_prefix("BTN_")) {
                token = "KEY_" + token;
            }

            sb.append(token);
            current = sb.str;
            grabbing = false;
            button.label = display_for(current);
            value_changed(current);
            return true;
        }

        static bool is_modifier_only(uint keyval) {
            return keyval == Gdk.Key.Shift_L     || keyval == Gdk.Key.Shift_R
                || keyval == Gdk.Key.Control_L   || keyval == Gdk.Key.Control_R
                || keyval == Gdk.Key.Alt_L       || keyval == Gdk.Key.Alt_R
                || keyval == Gdk.Key.Super_L     || keyval == Gdk.Key.Super_R
                || keyval == Gdk.Key.Meta_L      || keyval == Gdk.Key.Meta_R
                || keyval == Gdk.Key.Caps_Lock;
        }

        static string display_for(string s) {
            if (s == null || s == "" || s == "none") return "Unset";
            return s;
        }
    }
}
