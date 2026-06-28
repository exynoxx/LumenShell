using Gtk;

// Minimal, theme-friendly styling — we deliberately do NOT override the window
// background so the dialog inherits the system GTK theme (light/dark) and looks
// native, the way polkit-gnome/polkit-kde dialogs do.
public const string AGENT_CSS = """
    .polkit-title   { font-weight: bold; font-size: 13pt; }
    .polkit-message { opacity: 0.85; }
    .polkit-prompt  { opacity: 0.85; }
    .polkit-status  { opacity: 0.75; }
    .polkit-error   { color: #e05252; opacity: 1.0; }
""";

// AuthDialog — the password prompt. A plain (non-layer-shell) top-level so the
// compositor floats and focuses it like any normal dialog. The dialog is dumb:
// it emits submit/cancel/identity_changed and exposes show_prompt/show_error/…
// setters; AuthFlow owns all the state and the PolkitAgent.Session.
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
    // re-emitting cancel. Distinct from a user-initiated close (X button / Esc),
    // which must cancel the pending authentication.
    public void dismiss() {
        closing = true;
        close();
    }

    public AuthDialog(Gtk.Application app, string message, string icon_name,
                      GLib.List<Polkit.Identity> identities,
                      Polkit.Identity? chosen) {
        Object();

        set_title("Authentication Required");
        set_modal(true);
        set_resizable(false);
        set_default_size(430, -1);
        add_css_class("polkit-dialog");

        var arr = new Polkit.Identity[0];
        foreach (var id in identities) arr += id;
        ids = arr;

        var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, 16) {
            margin_top = 22, margin_bottom = 20,
            margin_start = 22, margin_end = 22,
        };

        // Header: icon + title + the polkit-supplied message.
        var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 14);
        var img = new Gtk.Image.from_icon_name(
            icon_name != "" ? icon_name : "dialog-password");
        img.pixel_size = 48;
        img.valign = Gtk.Align.START;
        header.append(img);

        var titles = new Gtk.Box(Gtk.Orientation.VERTICAL, 4) { hexpand = true };
        var title = new Gtk.Label("Authentication Required") {
            halign = Gtk.Align.START, xalign = 0,
        };
        title.add_css_class("polkit-title");
        var msg = new Gtk.Label(message) {
            halign = Gtk.Align.START, xalign = 0, wrap = true, max_width_chars = 44,
        };
        msg.add_css_class("polkit-message");
        titles.append(title);
        titles.append(msg);
        header.append(titles);
        outer.append(header);

        // When polkit offers more than one identity (e.g. root + several admin
        // users), let the user pick which one to authenticate as.
        if (arr.length > 1) {
            var names = new string[0];
            foreach (var id in arr) names += identity_label(id);
            var dropdown = new Gtk.DropDown.from_strings(names);
            for (uint i = 0; i < arr.length; i++)
                if (chosen != null && arr[i].equal(chosen)) dropdown.selected = i;
            dropdown.notify["selected"].connect(() => {
                var sel = dropdown.selected;
                if (sel < arr.length) identity_changed(arr[sel]);
            });
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
            row.append(new Gtk.Label("Authenticate as:") {
                halign = Gtk.Align.START,
            });
            row.append(dropdown);
            outer.append(row);
        }

        prompt_label = new Gtk.Label("Password:") {
            halign = Gtk.Align.START, xalign = 0,
        };
        prompt_label.add_css_class("polkit-prompt");
        outer.append(prompt_label);

        entry = new Gtk.PasswordEntry() { show_peek_icon = true, hexpand = true };
        entry.activate.connect(() => { lpa_dbg("dialog: entry.activate (Enter)"); submit(entry.get_text()); });
        outer.append(entry);

        status_label = new Gtk.Label("") {
            halign = Gtk.Align.START, xalign = 0, visible = false,
            wrap = true, max_width_chars = 44,
        };
        status_label.add_css_class("polkit-status");
        outer.append(status_label);

        var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
            halign = Gtk.Align.END,
        };
        var cancel_btn = new Gtk.Button.with_label("Cancel");
        cancel_btn.clicked.connect(() => { lpa_dbg("dialog: Cancel button clicked"); cancel(); });
        auth_button = new Gtk.Button.with_label("Authenticate");
        auth_button.add_css_class("suggested-action");
        auth_button.clicked.connect(() => { lpa_dbg("dialog: Authenticate button clicked"); submit(entry.get_text()); });
        buttons.append(cancel_btn);
        buttons.append(auth_button);
        outer.append(buttons);

        set_child(outer);

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

        // RAW pointer probe — does ANY click reach this surface at all?
        var probe = new Gtk.GestureClick();
        probe.set_button(0);  // any button
        probe.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        probe.pressed.connect((n, x, y) => lpa_dbg("dialog: RAW pointer pressed at %.0f,%.0f (n=%d)", x, y, n));
        ((Gtk.Widget) this).add_controller(probe);

        var focus = new Gtk.EventControllerFocus();
        focus.enter.connect(() => lpa_dbg("dialog: focus ENTER"));
        focus.leave.connect(() => lpa_dbg("dialog: focus LEAVE"));
        ((Gtk.Widget) this).add_controller(focus);

        map.connect(() => { lpa_dbg("dialog: map (is_active=%s)", this.is_active.to_string()); entry.grab_focus(); });
        notify["is-active"].connect(() => lpa_dbg("dialog: is-active now %s", this.is_active.to_string()));
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
