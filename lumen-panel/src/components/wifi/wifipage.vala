using Gtk;

public class WifiPage : Gtk.Box {

    const int PAD          = 14;
    const int HEADER_H     = 44;
    const int PASS_H       = 54;

    WifiService service;

    Gtk.Label  title_label;
    Gtk.Button refresh_btn;
    Gtk.Switch power_switch;
    LumenChip  conn_chip;
    bool       syncing_power = false;

    Gtk.ScrolledWindow scroll;
    Gtk.Box list_box;
    Gtk.Label empty_label;

    Gtk.Box        password_panel;
    Gtk.Box        controls_row;
    LumenTextField password_field;
    Gtk.ToggleButton reveal_btn;
    Gtk.Box        spacer;
    Gtk.Button     connect_btn;
    Gtk.Label      connected_label;
    Gtk.Label      status_label;

    Gee.ArrayList<WifiRow> rows = new Gee.ArrayList<WifiRow>();
    WifiNet[] sorted_nets = {};

    // Selection is tracked by SSID, not list index, so it survives the row
    // rebuilds triggered by background scans / state changes.
    string selected_ssid = "";

    // Sticky error for the in-flight selection — kept across rebuilds until the
    // user picks a different network or a connect succeeds.
    string error_ssid = "";
    string error_msg  = "";

    static Gdk.RGBA chip_online  = Utils.rgba(0.18f, 0.88f, 0.42f, 1f);
    static Gdk.RGBA chip_offline = Utils.rgba(0.52f, 0.52f, 0.57f, 1f);

    public WifiPage (WifiService service) {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.service = service;
        add_css_class("wifi-page");
        set_size_request(440, 400);

        build_header();
        append(build_separator());
        build_list();
        append(build_separator());
        build_password_panel();
        update_header();

        service.state_changed.connect(on_service_changed);
        service.connect_result.connect(on_connect_result);
        service.refresh_scan(false);
    }

    Gtk.Widget build_separator () {
        var sep = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
            height_request = 1,
            margin_start = PAD,
            margin_end = PAD,
        };
        sep.add_css_class("lumen-separator");
        return sep;
    }

    void build_header () {
        var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
            height_request = HEADER_H,
            margin_start = PAD,
            margin_end = PAD,
        };

        title_label = new Gtk.Label("WiFi") {
            xalign = 0,
            valign = Gtk.Align.CENTER,
        };
        title_label.add_css_class("page-title");
        header.append(title_label);

        refresh_btn = new Gtk.Button.with_label("Refresh") {
            valign = Gtk.Align.CENTER,
        };
        refresh_btn.add_css_class("lumen-button");
        refresh_btn.clicked.connect(() => service.refresh_scan(true));
        header.append(refresh_btn);

        power_switch = new Gtk.Switch() {
            valign = Gtk.Align.CENTER,
        };
        power_switch.add_css_class("lumen-switch");
        // Guard against the programmatic sync in update_header() looping back
        // into set_radio(); only user toggles should drive the radio.
        power_switch.notify["active"].connect(() => {
            if (syncing_power) return;
            service.set_radio(power_switch.active);
        });
        header.append(power_switch);

        var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true };
        header.append(spacer);

        conn_chip = new LumenChip() { valign = Gtk.Align.CENTER };
        header.append(conn_chip);

        append(header);
    }

    void build_list () {
        list_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
            hexpand = true,
        };
        list_box.add_css_class("wifi-list");

        scroll = new Gtk.ScrolledWindow() {
            child = list_box,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
            vexpand = true,
            min_content_height = 180,
        };
        scroll.add_css_class("wifi-scroll");

        // Centered placeholder shown when the radio is off or no networks are
        // visible yet — overlaid on the (empty) scroll area.
        empty_label = new Gtk.Label("") {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            can_target = false,
            visible = false,
        };
        empty_label.add_css_class("wifi-empty");

        var overlay = new Gtk.Overlay() { vexpand = true };
        overlay.set_child(scroll);
        overlay.add_overlay(empty_label);
        append(overlay);
    }

    void build_password_panel () {
        password_panel = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
            margin_start = PAD,
            margin_end = PAD,
            visible = false,
        };

        controls_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
            height_request = PASS_H,
        };

        password_field = new LumenTextField() {
            placeholder = "Password…",
            obscure_text = true,
            hexpand = true,
            valign = Gtk.Align.CENTER,
        };
        password_field.submitted.connect(do_connect);
        password_field.cancelled.connect(close_password_panel);
        controls_row.append(password_field);

        connected_label = new Gtk.Label("Connected") {
            xalign = 0,
            valign = Gtk.Align.CENTER,
            visible = false,
        };
        connected_label.add_css_class("connected-label");
        controls_row.append(connected_label);

        // Fills the row (keeping Connect pinned right) when neither the
        // password field nor the connected label is taking the space.
        spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true };
        controls_row.append(spacer);

        reveal_btn = new Gtk.ToggleButton.with_label("Show") {
            valign = Gtk.Align.CENTER,
            visible = false,
        };
        reveal_btn.add_css_class("lumen-button");
        reveal_btn.add_css_class("reveal-toggle");
        reveal_btn.toggled.connect(() => {
            password_field.obscure_text = !reveal_btn.active;
            reveal_btn.label = reveal_btn.active ? "Hide" : "Show";
        });
        controls_row.append(reveal_btn);

        connect_btn = new Gtk.Button.with_label("Connect") {
            valign = Gtk.Align.CENTER,
            width_request = 100,
        };
        connect_btn.add_css_class("lumen-button");
        connect_btn.clicked.connect(() => {
            if (selected_is_connected()) do_disconnect();
            else                          do_connect();
        });
        controls_row.append(connect_btn);

        password_panel.append(controls_row);

        status_label = new Gtk.Label("") {
            xalign = 0,
            margin_bottom = 8,
            visible = false,
        };
        status_label.add_css_class("wifi-status");
        password_panel.append(status_label);

        append(password_panel);
    }

    int index_of (string ssid) {
        for (int i = 0; i < sorted_nets.length; i++)
            if (sorted_nets[i].ssid == ssid) return i;
        return -1;
    }

    bool selected_is_connected () {
        return selected_ssid != "" && selected_ssid == service.connected_ssid;
    }

    void set_status (string msg, bool is_error) {
        status_label.label = msg;
        status_label.visible = msg != "";
        if (is_error) status_label.add_css_class("error");
        else          status_label.remove_css_class("error");
        if (is_error) password_field.add_css_class("error");
        else          password_field.remove_css_class("error");
    }

    void do_connect () {
        int idx = index_of(selected_ssid);
        if (idx < 0) return;
        var net = sorted_nets[idx];

        // Saved networks (and open ones) join without a typed passphrase. A
        // password typed into a revealed field always overrides — that covers
        // a saved network whose stored passphrase is now stale.
        string pass = password_field.visible ? password_field.text : "";
        bool from_saved = net.is_saved && pass == "";

        // Clear any prior error and reflect the in-flight attempt immediately;
        // the rest of the panel state is recomputed from service.connecting_ssid.
        error_ssid = ""; error_msg = "";
        service.connect_to(net.ssid, pass, from_saved);
    }

    void do_disconnect () {
        service.disconnect_active();
        close_password_panel();
    }

    void close_password_panel () {
        selected_ssid = "";
        error_ssid = ""; error_msg = "";
        foreach (var r in rows) r.selected = false;
        password_field.text = "";
        reveal_btn.active = false;
        password_field.obscure_text = true;
        password_field.blur();
        set_status("", false);
        password_panel.visible = false;
        queue_draw();
    }

    void select_ssid (string ssid, bool reset_input) {
        selected_ssid = ssid;
        foreach (var r in rows) r.selected = (r.ssid == ssid);
        if (reset_input) {
            password_field.text = "";
            reveal_btn.active = false;
            password_field.obscure_text = true;
            error_ssid = ""; error_msg = "";
        }
        update_password_panel();
        if (password_field.visible && password_field.text == "")
            password_field.grab_text_focus();
    }

    // Recompute the whole password panel from the selected network plus live
    // service state (connected / connecting) and any sticky error. Idempotent —
    // safe to call after every rebuild.
    void update_password_panel () {
        int idx = index_of(selected_ssid);
        if (idx < 0) {
            password_panel.visible = false;
            return;
        }
        var net = sorted_nets[idx];
        bool connected  = net.ssid == service.connected_ssid;
        bool connecting = net.ssid == service.connecting_ssid;
        bool has_error  = net.ssid == error_ssid && error_msg != "";

        // Prompt for a password only on secured networks that aren't saved or
        // already connected — or while recovering from a rejected passphrase.
        bool needs_password = !connected && net.is_secured() && (!net.is_saved || has_error);

        password_field.visible  = needs_password;
        reveal_btn.visible      = needs_password;
        connected_label.visible = connected;
        spacer.visible          = !needs_password && !connected;

        if (connected) {
            connect_btn.label = "Disconnect";
            connect_btn.add_css_class("danger");
        } else {
            connect_btn.remove_css_class("danger");
            connect_btn.label = connecting ? "Connecting…" : "Connect";
        }
        connect_btn.sensitive    = !connecting;
        password_field.sensitive = !connecting;

        if (has_error)
            set_status(error_msg, true);
        else if (!connected && net.is_saved && !needs_password)
            set_status("Saved network", false);
        else
            set_status("", false);

        password_panel.visible = true;
    }

    void on_connect_result (string ssid, WifiConnectResult res) {
        if (ssid != selected_ssid) return;

        if (res == WifiConnectResult.SUCCESS) {
            close_password_panel();
            return;
        }

        error_ssid = ssid;
        error_msg  = (res == WifiConnectResult.BAD_PASSWORD)
            ? "Incorrect password — try again"
            : "Connection failed";
        // Re-prompt (revealing the field for saved nets with a stale key) and
        // clear whatever was typed so the retry starts fresh.
        password_field.text = "";
        reveal_btn.active = false;
        password_field.obscure_text = true;
        update_password_panel();
        if (password_field.visible) password_field.grab_text_focus();
    }

    void on_service_changed () {
        rebuild_rows();
        refresh_btn.label = service.scanning ? "Scanning" : "Refresh";

        // Re-anchor the selection to the same SSID if it's still visible.
        if (selected_ssid != "" && index_of(selected_ssid) < 0
            && selected_ssid != service.connecting_ssid) {
            close_password_panel();
        } else if (selected_ssid != "") {
            select_ssid(selected_ssid, false);
        }

        update_header();
    }

    void rebuild_rows () {
        Gtk.Widget? w;
        while ((w = list_box.get_first_child()) != null) list_box.remove(w);
        rows.clear();

        // Keep the currently-connected network pinned to the top of the list,
        // preserving nmcli's order for everything else.
        var ordered = new Gee.ArrayList<WifiNet>();
        foreach (var net in service.nets)
            if (net.ssid == service.connected_ssid) ordered.add(net);
        foreach (var net in service.nets)
            if (net.ssid != service.connected_ssid) ordered.add(net);
        sorted_nets = ordered.to_array();

        foreach (var net in sorted_nets) {
            var row = new WifiRow(net, net.ssid == service.connected_ssid);
            string captured_ssid = net.ssid;
            row.activated.connect(() => {
                if (selected_ssid == captured_ssid) close_password_panel();
                else                                 select_ssid(captured_ssid, true);
            });
            row.disconnect_clicked.connect(do_disconnect);
            rows.add(row);
            list_box.append(row);
        }
    }

    void update_header () {
        if (power_switch.active != service.enabled) {
            syncing_power = true;
            power_switch.active = service.enabled;
            syncing_power = false;
        }
        refresh_btn.sensitive = service.enabled;

        string ssid = service.connected_ssid;
        bool online = ssid != "" && ssid != "--";
        conn_chip.set_text(online ? "●  " + ssid
                                   : (service.enabled ? "●  Offline" : "●  Off"));
        conn_chip.set_text_color(online ? chip_online : chip_offline);

        if (!service.enabled) {
            empty_label.label = "WiFi is off";
            empty_label.visible = true;
        } else if (rows.size == 0) {
            empty_label.label = service.scanning ? "Scanning…" : "No networks found";
            empty_label.visible = true;
        } else {
            empty_label.visible = false;
        }
    }
}
