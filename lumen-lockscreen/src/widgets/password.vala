using Gtk;

// Password input column: the entry, a caps-lock warning, and a status line that
// doubles as the error/working banner. Emits `submitted` on Enter. The manager
// drives the rest (disable while authenticating, set_error / shake on failure).
public class PasswordField : Gtk.Box {

    public signal void submitted(string password);

    private Gtk.PasswordEntry entry;
    private Gtk.Label caps_label;
    private Gtk.Label status_label;

    public PasswordField() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);
        set_halign(Gtk.Align.CENTER);

        entry = new Gtk.PasswordEntry() {
            show_peek_icon = true,
            placeholder_text = "Password",
            width_request = 280,
            halign = Gtk.Align.CENTER,
        };
        entry.add_css_class("lockscreen-entry");
        entry.activate.connect(() => {
            submitted(entry.text);
        });
        append(entry);

        caps_label = new Gtk.Label("⇪ Caps Lock is on") {
            halign = Gtk.Align.CENTER,
            visible = false,
        };
        caps_label.add_css_class("lockscreen-caps");
        append(caps_label);

        status_label = new Gtk.Label("") {
            halign = Gtk.Align.CENTER,
            visible = false,
        };
        status_label.add_css_class("lockscreen-status");
        append(status_label);

        // Caps-lock detection: GTK4 exposes no caps query, so watch the
        // modifier state on every key event into the entry.
        var keys = new Gtk.EventControllerKey();
        keys.key_pressed.connect((kv, kc, state) => {
            caps_label.visible = (state & Gdk.ModifierType.LOCK_MASK) != 0;
            return false;
        });
        keys.key_released.connect((kv, kc, state) => {
            caps_label.visible = (state & Gdk.ModifierType.LOCK_MASK) != 0;
        });
        entry.add_controller(keys);
    }

    public void focus_entry() {
        entry.grab_focus();
    }

    public void clear() {
        entry.text = "";
    }

    // Disable input + show a working banner while PAM runs.
    public void set_busy(bool busy) {
        entry.sensitive = !busy;
        if (busy) {
            status_label.remove_css_class("lockscreen-status-error");
            status_label.label = "Signing in…";
            status_label.visible = true;
        }
    }

    // Re-enable for another attempt (e.g. after a wrong password).
    public void set_input_enabled(bool enabled) {
        entry.sensitive = enabled;
        if (enabled) focus_entry();
    }

    public void set_error(string message) {
        status_label.add_css_class("lockscreen-status-error");
        status_label.label = message;
        status_label.visible = true;
        // Brief shake to signal rejection.
        add_css_class("shake");
        Timeout.add(420, () => { remove_css_class("shake"); return Source.REMOVE; });
    }

    public void clear_status() {
        status_label.visible = false;
        status_label.label = "";
        status_label.remove_css_class("lockscreen-status-error");
    }
}
