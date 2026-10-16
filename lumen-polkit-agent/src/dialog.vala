public const string AGENT_CSS = """
    .polkit-bar     { background-color: rgba(0,0,0,0.92); }
    .polkit-title   { font-weight: bold; font-size: 14pt; color: #ffffff; }
    .polkit-message { color: #ffffff; opacity: 0.80; }
    .polkit-prompt  { color: #ffffff; opacity: 0.85; }
    .polkit-status  { color: #ffffff; opacity: 0.85; }
    .polkit-error   { color: #ff6b6b; opacity: 1.0; }
""";

// Layer-shell OVERLAY with EXCLUSIVE keyboard, not a toplevel: Wayfire doesn't
// reliably focus a floating xdg dialog. AuthFlow owns all state.
public class AuthDialog : Gtk.Window {

    public signal void submit(string password);
    public signal void cancel();
    public signal void identity_changed(Polkit.Identity id);

    private Gtk.PasswordEntry entry;
    private Gtk.Label   prompt_label;
    private Gtk.Label   status_label;
    private Gtk.Button  auth_button;
    private bool        closing = false;

    // Programmatic close: unlike a user close (Esc), does NOT emit cancel.
    public void dismiss() {
        closing = true;
        close();
    }

    public AuthDialog(string message, string icon_name,
                      GLib.List<Polkit.Identity> identities,
                      Polkit.Identity? chosen) {
        Object();

        set_title("Authentication Required");

        // Init MUST happen before the window is first realized/mapped.
        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-polkit");
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.EXCLUSIVE);
        // LEFT+RIGHT only: full width, vertically centred by the compositor.
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,  true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);

        add_css_class("polkit-bar");

        var arr = new Polkit.Identity[0];
        foreach (var id in identities) arr += id;

        var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 22) {
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
            margin_top = 30, margin_bottom = 30,
            margin_start = 28, margin_end = 28,
        };

        var img = new Gtk.Image.from_icon_name(
            icon_name != "" ? icon_name : "dialog-password");
        img.pixel_size = 44;
        img.valign = Gtk.Align.CENTER;
        bar.append(img);

        var titles = new Gtk.Box(Gtk.Orientation.VERTICAL, 3) {
            valign = Gtk.Align.CENTER,
        };
        var title = new Gtk.Label("Authentication Required") {
            halign = Gtk.Align.START, xalign = 0,
        };
        title.add_css_class("polkit-title");
        var msg = new Gtk.Label(message) {
            halign = Gtk.Align.START, xalign = 0, wrap = true, max_width_chars = 50,
        };
        msg.add_css_class("polkit-message");
        status_label = new Gtk.Label("") {
            halign = Gtk.Align.START, xalign = 0, visible = false,
            wrap = true, max_width_chars = 50,
        };
        status_label.add_css_class("polkit-status");
        titles.append(title);
        titles.append(msg);
        titles.append(status_label);
        bar.append(titles);

        if (arr.length > 1) {
            var names = new string[0];
            foreach (var id in arr) names += identity_label(id);
            var dropdown = new Gtk.DropDown.from_strings(names) {
                valign = Gtk.Align.CENTER,
            };
            for (uint i = 0; i < arr.length; i++)
                if (chosen != null && arr[i].equal(chosen)) dropdown.selected = i;
            dropdown.notify["selected"].connect(() => {
                var sel = dropdown.selected;
                if (sel < arr.length) identity_changed(arr[sel]);
            });
            var asl = new Gtk.Label("as:") { valign = Gtk.Align.CENTER };
            asl.add_css_class("polkit-prompt");
            bar.append(asl);
            bar.append(dropdown);
        }

        prompt_label = new Gtk.Label("Password:") { valign = Gtk.Align.CENTER };
        prompt_label.add_css_class("polkit-prompt");
        bar.append(prompt_label);

        entry = new Gtk.PasswordEntry() {
            show_peek_icon = true, valign = Gtk.Align.CENTER, width_request = 240,
        };
        entry.activate.connect(() => { GLib.debug("dialog: entry.activate (Enter)"); submit(entry.get_text()); });
        bar.append(entry);

        var cancel_btn = new Gtk.Button.with_label("Cancel") {
            valign = Gtk.Align.CENTER,
        };
        cancel_btn.clicked.connect(() => { GLib.debug("dialog: Cancel button clicked"); cancel(); });
        auth_button = new Gtk.Button.with_label("Authenticate") {
            valign = Gtk.Align.CENTER,
        };
        auth_button.add_css_class("suggested-action");
        auth_button.clicked.connect(() => { GLib.debug("dialog: Authenticate button clicked"); submit(entry.get_text()); });
        bar.append(cancel_btn);
        bar.append(auth_button);

        set_child(bar);

        // Esc and the window-manager close button both count as Cancel.
        var key = new Gtk.EventControllerKey();
        key.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        key.key_pressed.connect((kv, kc, st) => {
            GLib.debug("dialog: key_pressed keyval=%u", kv);
            if (kv == Gdk.Key.Escape) { cancel(); return true; }
            return false;
        });
        ((Gtk.Widget) this).add_controller(key);
        // Returning true would VETO the close forever; always allow it, and
        // cancel only on a genuine user close, not dismiss().
        close_request.connect(() => {
            GLib.debug("dialog: close_request (closing=%s)", closing.to_string());
            if (!closing) cancel();
            return false;
        });

        map.connect(() => { entry.grab_focus(); });
    }

    private static string identity_label(Polkit.Identity id) {
        if (id is Polkit.UnixUser) {
            var n = ((Polkit.UnixUser) id).get_name();
            if (n != null) return n;
        }
        return id.to_string();
    }

    // Echo requests are ignored: the field stays masked.
    public void show_prompt(string text) {
        prompt_label.label = text;
        set_busy(false);
        entry.grab_focus();
    }

    public void show_error_text(string t) {
        status_label.remove_css_class("polkit-status");
        status_label.add_css_class("polkit-error");
        status_label.label = t;
        status_label.visible = true;
    }

    public void show_info_text(string t) {
        status_label.remove_css_class("polkit-error");
        status_label.add_css_class("polkit-status");
        status_label.label = t;
        status_label.visible = true;
    }

    public void clear_password() {
        entry.set_text("");
    }

    public void set_busy(bool busy) {
        entry.sensitive       = !busy;
        auth_button.sensitive = !busy;
        if (busy) {
            status_label.remove_css_class("polkit-error");
            status_label.add_css_class("polkit-status");
            status_label.label   = "Authenticating…";
            status_label.visible = true;
        }
    }
}
