namespace LumenSettings {

    public class BindingRow : Adw.ActionRow {
        public signal void value_changed(string binding);

        Gtk.Button button;
        string current;
        bool grabbing = false;
        // Modifiers held during a grab with no other key yet; releasing one
        // commits a modifier-only binding such as "<super>".
        string[] pending_mods = {};
        Gtk.EventControllerKey key_ctl;

        public BindingRow(string title, string initial, string subtitle = "") {
            Object(title: title, subtitle: subtitle, use_markup: false);
            current = initial;

            button = new Gtk.Button.with_label(display_for(current));
            button.clicked.connect(start_grab);
            button.valign = Gtk.Align.CENTER;
            add_suffix(button);

            key_ctl = new Gtk.EventControllerKey();
            key_ctl.key_pressed.connect(on_key_pressed);
            key_ctl.key_released.connect(on_key_released);
            button.add_controller(key_ctl);

            var rclick = new Gtk.GestureClick() { button = Gdk.BUTTON_SECONDARY };
            rclick.pressed.connect((n, x, y) => {
                current = "";
                button.label = display_for(current);
                value_changed(current);
            });
            button.add_controller(rclick);
        }

        void start_grab() {
            grabbing = true;
            pending_mods = {};
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
            if (is_modifier_only(keyval)) {
                string? m = modifier_token(keyval);
                if (m != null && !(m in pending_mods)) pending_mods += m;
                return true;
            }
            pending_mods = {};

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

        void on_key_released(uint keyval, uint keycode, Gdk.ModifierType state) {
            if (!grabbing || pending_mods.length == 0 || !is_modifier_only(keyval)) return;
            // Canonical order, matching the key-press path.
            var sb = new StringBuilder();
            foreach (var m in new string[] { "<shift>", "<ctrl>", "<alt>", "<super>", "<meta>" }) {
                if (m in pending_mods) sb.append(m).append(" ");
            }
            pending_mods = {};
            current = sb.str.strip();
            grabbing = false;
            button.label = display_for(current);
            value_changed(current);
        }

        static string? modifier_token(uint keyval) {
            if (keyval == Gdk.Key.Shift_L   || keyval == Gdk.Key.Shift_R)   return "<shift>";
            if (keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R) return "<ctrl>";
            if (keyval == Gdk.Key.Alt_L     || keyval == Gdk.Key.Alt_R)     return "<alt>";
            if (keyval == Gdk.Key.Super_L   || keyval == Gdk.Key.Super_R)   return "<super>";
            if (keyval == Gdk.Key.Meta_L    || keyval == Gdk.Key.Meta_R)    return "<meta>";
            return null;
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
