using Gtk;

// Apple-style password pill: a translucent rounded field with a trailing
// circular arrow "go" button. Enter OR the arrow submits — including an empty
// string, which is how no-password users log in (PAM nullok succeeds). Below
// it sit the caps-lock warning and the error/working status line.
public class PasswordField : Gtk.Box {

    public signal void submitted(string password);

    private Gtk.Text   entry;
    private Gtk.Button go;
    private Gtk.Label  caps_label;
    private Gtk.Label  status_label;

    public PasswordField() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 10);
        set_halign(Gtk.Align.CENTER);

        // The pill: [ masked text .......... (→) ]
        var pill = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4) {
            halign = Gtk.Align.CENTER,
        };
        pill.add_css_class("lockscreen-pill");

        entry = new Gtk.Text() {
            visibility = false,                 // masked
            placeholder_text = "Enter Password",
            hexpand = true,
            width_request = 230,
            valign = Gtk.Align.CENTER,
        };
        entry.add_css_class("lockscreen-pill-text");
        entry.activate.connect(() => submitted(entry.text));
        pill.append(entry);

        go = new Gtk.Button() {
            valign = Gtk.Align.CENTER,
            tooltip_text = "Log in",
        };
        go.add_css_class("lockscreen-go");
        go.add_css_class("circular");
        go.child = new Gtk.Image.from_icon_name("go-next-symbolic") { pixel_size = 16 };
        go.clicked.connect(() => submitted(entry.text));
        pill.append(go);

        append(pill);

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
        // modifier state on key events into the field.
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
        go.sensitive    = !busy;
        if (busy) {
            status_label.remove_css_class("lockscreen-status-error");
            status_label.label = "Signing in…";
            status_label.visible = true;
        }
    }

    public void set_input_enabled(bool enabled) {
        entry.sensitive = enabled;
        go.sensitive    = enabled;
        if (enabled) focus_entry();
    }

    public void set_error(string message) {
        status_label.add_css_class("lockscreen-status-error");
        status_label.label = message;
        status_label.visible = true;
        add_css_class("shake");
        Timeout.add(420, () => { remove_css_class("shake"); return Source.REMOVE; });
    }

    public void clear_status() {
        status_label.visible = false;
        status_label.label = "";
        status_label.remove_css_class("lockscreen-status-error");
    }
}
