using Gtk;

// Black "pause-screen" bar styling. The bar is a full-width OVERLAY layer-shell
// surface, so it owns its own background (no system theme to inherit, unlike the
// old floating dialog) — paint it black and force the text white.
public const string AGENT_CSS = """
    .polkit-bar     { background-color: rgba(0,0,0,0.92); }
    .polkit-title   { font-weight: bold; font-size: 14pt; color: #ffffff; }
    .polkit-message { color: #ffffff; opacity: 0.80; }
    .polkit-prompt  { color: #ffffff; opacity: 0.85; }
    .polkit-status  { color: #ffffff; opacity: 0.85; }
    .polkit-error   { color: #ff6b6b; opacity: 1.0; }
""";

// AuthDialog — the password prompt, rendered as a horizontal black bar spanning
// the full screen width and centered vertically (a game-style pause overlay).
//
// It is a gtk4-layer-shell OVERLAY surface with EXCLUSIVE keyboard, NOT a plain
// toplevel: a bare Wayfire session wouldn't reliably focus a floating xdg dialog
// (the old "dialog renders but buttons do nothing" bug), whereas an EXCLUSIVE
// layer surface grabs the keyboard unconditionally for as long as the prompt is
// up — exactly what an authentication gate wants.
//
// The dialog is dumb: it emits submit/cancel/identity_changed and exposes
// show_prompt/show_error/… setters; AuthFlow owns all the state and the
// PolkitAgent.Session.
public class AuthDialog : Gtk.Window {

    public signal void submit(string password);
    public signal void cancel();
    public signal void identity_changed(Polkit.Identity id);

    private Gtk.PasswordEntry entry;
    private Gtk.Label   prompt_label;
    private Gtk.Label   status_label;
    private Gtk.Button  auth_button;
    private Polkit.Identity[] ids;
    private bool        closing = false;

    // Programmatic close (the flow finished): tear the window down WITHOUT
    // re-emitting cancel. Distinct from a user-initiated close (Esc), which must
    // cancel the pending authentication.
    public void dismiss() {
        closing = true;
        close();
    }

    public AuthDialog(Gtk.Application app, string message, string icon_name,
                      GLib.List<Polkit.Identity> identities,
                      Polkit.Identity? chosen) {
        Object();

        set_title("Authentication Required");

        // --- layer-shell: full-width OVERLAY bar, vertically centered ---------
        // Init MUST happen before the window is first realized/mapped.
        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-polkit");
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
        // EXCLUSIVE: the bar grabs the keyboard for the whole prompt — this is
        // the load-bearing fix over the old floating dialog.
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.EXCLUSIVE);
        // Anchor LEFT+RIGHT only → spans the full width; leaving TOP/BOTTOM
        // unanchored lets the compositor center the bar vertically.
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,  true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);

        add_css_class("polkit-bar");

        var arr = new Polkit.Identity[0];
        foreach (var id in identities) arr += id;
        ids = arr;

        // Single horizontal row, centered in the full-width bar. Generous
        // vertical margins give it the height of a pause-screen banner.
        var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 22) {
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
            margin_top = 30, margin_bottom = 30,
            margin_start = 28, margin_end = 28,
        };

        // Icon + title/message/status stacked at the left of the row.
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

        // When polkit offers more than one identity (e.g. root + several admin
        // users), let the user pick which one to authenticate as.
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
        entry.activate.connect(() => { lpa_dbg("dialog: entry.activate (Enter)"); submit(entry.get_text()); });
        bar.append(entry);

        var cancel_btn = new Gtk.Button.with_label("Cancel") {
            valign = Gtk.Align.CENTER,
        };
        cancel_btn.clicked.connect(() => { lpa_dbg("dialog: Cancel button clicked"); cancel(); });
        auth_button = new Gtk.Button.with_label("Authenticate") {
            valign = Gtk.Align.CENTER,
        };
        auth_button.add_css_class("suggested-action");
        auth_button.clicked.connect(() => { lpa_dbg("dialog: Authenticate button clicked"); submit(entry.get_text()); });
        bar.append(cancel_btn);
        bar.append(auth_button);

        set_child(bar);

        // Esc and the window-manager close button both count as Cancel.
        var key = new Gtk.EventControllerKey();
        key.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        key.key_pressed.connect((kv, kc, st) => {
            lpa_dbg("dialog: key_pressed keyval=%u", kv);
            if (kv == Gdk.Key.Escape) { cancel(); return true; }
            return false;
        });
        ((Gtk.Widget) this).add_controller(key);
        // Returning true here would VETO the close — the window could then never
        // be destroyed, by us or the user. Always return false (allow close);
        // emit cancel only for a genuine user close, not our own dismiss().
        close_request.connect(() => {
            lpa_dbg("dialog: close_request (closing=%s)", closing.to_string());
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

    // PAM prompt arrived ("Password:", or a custom message for e.g. fingerprint
    // backends). echo_on is currently informational — the field stays masked,
    // which is correct for the overwhelmingly common password case.
    public void show_prompt(string text, bool echo_on) {
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
