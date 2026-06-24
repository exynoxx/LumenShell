using Gtk;

// Inline Wi-Fi detail the Control Center slides to. macOS-faithful: a back
// header with a green power switch + scan spinner, the connected network pinned
// in its own card with a blue check, an "OTHER NETWORKS" group below, and an
// inline pill password card with a circular go-arrow. The selection / sticky-
// error logic is the proven flow carried over from the old WifiPage.
public class WifiDetail : CcDetail {

    WifiService service;

    Gtk.Switch  power_switch;
    Gtk.Button  refresh_btn;
    Gtk.Spinner spinner;
    bool        syncing_power = false;

    Gtk.Box            conn_card;
    Gtk.Label          others_caption;
    Gtk.ScrolledWindow others_scroll;
    Gtk.Box            others_card;
    Gtk.Label          empty_label;

    Gtk.Box          pass_card;
    LumenTextField   password_field;
    Gtk.ToggleButton reveal_btn;
    Gtk.Button       go_btn;
    Gtk.Button       connect_btn;
    Gtk.Label        status_label;

    Gee.ArrayList<WifiRow> rows = new Gee.ArrayList<WifiRow> ();
    WifiNet[] sorted_nets = {};

    // Tracked by SSID so it survives the row rebuilds from background scans.
    string selected_ssid = "";
    string error_ssid = "";
    string error_msg  = "";

    public WifiDetail (WifiService service) {
        base ();
        this.service = service;
        add_css_class ("wifi-detail");

        build_header ();
        build_content ();
        update_header ();

        service.state_changed.connect (on_service_changed);
        service.connect_result.connect (on_connect_result);
        service.refresh_scan (false);
    }

    void build_header () {
        var trailing = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            valign = Gtk.Align.CENTER,
        };

        spinner = new Gtk.Spinner () { valign = Gtk.Align.CENTER, visible = false };
        trailing.append (spinner);

        refresh_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        refresh_btn.add_css_class ("cc-icon-btn");
        var rlbl = new Gtk.Label ("⟲");
        refresh_btn.set_child (rlbl);
        refresh_btn.clicked.connect (() => service.refresh_scan (true));
        trailing.append (refresh_btn);

        power_switch = new Gtk.Switch () { valign = Gtk.Align.CENTER };
        power_switch.add_css_class ("lumen-switch");
        power_switch.notify["active"].connect (() => {
            if (syncing_power) return;
            service.set_radio (power_switch.active);
        });
        trailing.append (power_switch);

        append (make_header ("Wi-Fi", trailing));
    }

    void build_content () {
        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
            margin_start = 14, margin_end = 14, margin_bottom = 14, vexpand = true,
        };

        conn_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        conn_card.add_css_class ("cc-card");
        content.append (conn_card);

        others_caption = new Gtk.Label ("OTHER NETWORKS") {
            xalign = 0, margin_start = 4, margin_top = 4, visible = false,
        };
        others_caption.add_css_class ("cc-caption");
        content.append (others_caption);

        others_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        others_card.add_css_class ("cc-card");
        others_scroll = new Gtk.ScrolledWindow () {
            child = others_card,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
            vexpand = true,
            min_content_height = 200,
            max_content_height = 320,
            propagate_natural_height = true,
        };
        others_scroll.add_css_class ("cc-scroll");
        content.append (others_scroll);

        empty_label = new Gtk.Label ("") {
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
            vexpand = true, can_target = false, visible = false,
        };
        empty_label.add_css_class ("cc-empty");
        content.append (empty_label);

        build_pass_card ();
        content.append (pass_card);

        append (content);
    }

    void build_pass_card () {
        pass_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) { visible = false };
        pass_card.add_css_class ("cc-card");
        pass_card.add_css_class ("cc-pass");

        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            margin_start = 10, margin_end = 10, margin_top = 10, margin_bottom = 4,
        };

        password_field = new LumenTextField () {
            placeholder = "Password", obscure_text = true, hexpand = true,
            valign = Gtk.Align.CENTER,
        };
        password_field.submitted.connect (do_connect);
        password_field.cancelled.connect (close_password_panel);
        row.append (password_field);

        reveal_btn = new Gtk.ToggleButton () { valign = Gtk.Align.CENTER, visible = false };
        reveal_btn.add_css_class ("cc-icon-btn");
        reveal_btn.set_child (new Gtk.Label ("👁"));
        reveal_btn.toggled.connect (() => {
            password_field.obscure_text = !reveal_btn.active;
        });
        row.append (reveal_btn);

        go_btn = new Gtk.Button () { valign = Gtk.Align.CENTER, visible = false };
        go_btn.add_css_class ("cc-go");
        go_btn.set_child (new Gtk.Label ("→"));
        go_btn.clicked.connect (do_connect);
        row.append (go_btn);

        connect_btn = new Gtk.Button.with_label ("Connect") {
            valign = Gtk.Align.CENTER, hexpand = true, visible = false,
        };
        connect_btn.add_css_class ("lumen-button");
        connect_btn.clicked.connect (() => {
            if (selected_is_connected ()) do_disconnect ();
            else                          do_connect ();
        });
        row.append (connect_btn);

        pass_card.append (row);

        status_label = new Gtk.Label ("") {
            xalign = 0, margin_start = 12, margin_bottom = 8, visible = false,
        };
        status_label.add_css_class ("wifi-status");
        pass_card.append (status_label);
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
        if (is_error) status_label.add_css_class ("error");
        else          status_label.remove_css_class ("error");
        if (is_error) password_field.add_css_class ("error");
        else          password_field.remove_css_class ("error");
    }

    void do_connect () {
        int idx = index_of (selected_ssid);
        if (idx < 0) return;
        var net = sorted_nets[idx];

        string pass = password_field.visible ? password_field.text : "";
        bool from_saved = net.is_saved && pass == "";

        error_ssid = ""; error_msg = "";
        service.connect_to (net.ssid, pass, from_saved);
    }

    void do_disconnect () {
        service.disconnect_active ();
        close_password_panel ();
    }

    void close_password_panel () {
        selected_ssid = "";
        error_ssid = ""; error_msg = "";
        foreach (var r in rows) r.selected = false;
        password_field.text = "";
        reveal_btn.active = false;
        password_field.obscure_text = true;
        password_field.blur ();
        set_status ("", false);
        pass_card.visible = false;
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
        update_password_panel ();
        if (password_field.visible && password_field.text == "")
            password_field.grab_text_focus ();
    }

    // Recompute the password card from the selected network + live service state.
    // Idempotent — safe to call after every rebuild.
    void update_password_panel () {
        int idx = index_of (selected_ssid);
        if (idx < 0) { pass_card.visible = false; return; }
        var net = sorted_nets[idx];
        bool connected  = net.ssid == service.connected_ssid;
        bool connecting = net.ssid == service.connecting_ssid;
        bool has_error  = net.ssid == error_ssid && error_msg != "";

        bool needs_password = !connected && net.is_secured () && (!net.is_saved || has_error);

        password_field.visible = needs_password;
        reveal_btn.visible     = needs_password;
        go_btn.visible         = needs_password && !connecting;
        connect_btn.visible    = !needs_password;

        if (connected) {
            connect_btn.label = "Disconnect";
            connect_btn.add_css_class ("danger");
        } else {
            connect_btn.remove_css_class ("danger");
            connect_btn.label = connecting ? "Connecting…" : "Connect";
        }
        connect_btn.sensitive    = !connecting;
        password_field.sensitive = !connecting;
        go_btn.sensitive         = !connecting;

        if (has_error)
            set_status (error_msg, true);
        else if (!connected && net.is_saved && !needs_password)
            set_status ("Saved network", false);
        else
            set_status ("", false);

        pass_card.visible = true;
    }

    void on_connect_result (string ssid, WifiConnectResult res) {
        if (ssid != selected_ssid) return;

        if (res == WifiConnectResult.SUCCESS) {
            close_password_panel ();
            return;
        }

        error_ssid = ssid;
        error_msg  = (res == WifiConnectResult.BAD_PASSWORD)
            ? "Incorrect password — try again"
            : "Connection failed";
        password_field.text = "";
        reveal_btn.active = false;
        password_field.obscure_text = true;
        update_password_panel ();
        if (password_field.visible) password_field.grab_text_focus ();
    }

    void on_service_changed () {
        rebuild_rows ();

        if (selected_ssid != "" && index_of (selected_ssid) < 0
            && selected_ssid != service.connecting_ssid) {
            close_password_panel ();
        } else if (selected_ssid != "") {
            select_ssid (selected_ssid, false);
        }

        update_header ();
    }

    void rebuild_rows () {
        Gtk.Widget? w;
        while ((w = conn_card.get_first_child ()) != null)   conn_card.remove (w);
        while ((w = others_card.get_first_child ()) != null) others_card.remove (w);
        rows.clear ();

        // Connected network pinned first; nmcli order preserved for the rest.
        var ordered = new Gee.ArrayList<WifiNet> ();
        foreach (var net in service.nets)
            if (net.ssid == service.connected_ssid) ordered.add (net);
        foreach (var net in service.nets)
            if (net.ssid != service.connected_ssid) ordered.add (net);
        sorted_nets = ordered.to_array ();

        int other_count = 0;
        foreach (var net in sorted_nets)
            if (net.ssid != service.connected_ssid) other_count++;

        int others_seen = 0;
        foreach (var net in sorted_nets) {
            bool connected = net.ssid == service.connected_ssid;
            var row = new WifiRow (net, connected);
            string captured_ssid = net.ssid;
            row.activated.connect (() => {
                if (selected_ssid == captured_ssid) close_password_panel ();
                else                                select_ssid (captured_ssid, true);
            });
            rows.add (row);

            if (connected) {
                row.show_separator = false;
                conn_card.append (row);
            } else {
                others_seen++;
                row.show_separator = others_seen < other_count;
                others_card.append (row);
            }
        }
    }

    void update_header () {
        if (power_switch.active != service.enabled) {
            syncing_power = true;
            power_switch.active = service.enabled;
            syncing_power = false;
        }
        refresh_btn.sensitive = service.enabled;
        refresh_btn.visible   = !service.scanning;
        spinner.visible       = service.scanning;
        spinner.spinning      = service.scanning;

        bool has_conn   = service.connected_ssid != "" && service.connected_ssid != "--";
        bool has_others = false;
        foreach (var net in sorted_nets)
            if (net.ssid != service.connected_ssid) { has_others = true; break; }

        conn_card.visible      = has_conn;
        others_caption.visible = has_conn && has_others;
        others_scroll.visible  = has_others;

        if (!service.enabled) {
            empty_label.label = "Wi-Fi is off";
            empty_label.visible = true;
            others_scroll.visible = false;
            others_caption.visible = false;
        } else if (rows.size == 0) {
            empty_label.label = service.scanning ? "Scanning…" : "No networks found";
            empty_label.visible = true;
        } else {
            empty_label.visible = false;
        }
    }
}
