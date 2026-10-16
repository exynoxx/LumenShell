public class WifiDetail : CcListDetail {

    WifiService service;

    Gtk.Box   conn_card;
    Gtk.Label saved_caption;
    Gtk.Box   saved_card;
    Gtk.Label others_caption;
    Gtk.Box   others_card;

    Gtk.Box          pass_card;
    LumenTextField   password_field;
    Gtk.ToggleButton reveal_btn;
    Gtk.Button       go_btn;
    Gtk.Button       connect_btn;
    Gtk.Button       forget_btn;
    Gtk.Label        status_label;

    WifiNet[] sorted_nets = {};

    // Sticky per-SSID failure, so a background rescan doesn't wipe the message.
    string error_ssid = "";
    string error_msg  = "";

    public WifiDetail (WifiService service) {
        base ("Wi-Fi", "cc-wifi-detail");
        this.service = service;

        build_content ();
        update_view ();

        service.state_changed.connect (on_service_changed);
        service.connect_result.connect (on_connect_result);
        service.refresh_scan (false);
    }

    protected override void power_requested (bool on) { service.set_radio (on); }
    protected override void refresh_requested ()      { service.refresh_scan (true); }

    void build_content () {
        conn_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { visible = false };
        conn_card.add_css_class ("cc-card");
        content.append (conn_card);

        var lists_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) { hexpand = true };

        saved_caption = new Gtk.Label ("SAVED NETWORKS") {
            xalign = 0, margin_start = 4, visible = false,
        };
        saved_caption.add_css_class ("cc-caption");
        lists_box.append (saved_caption);

        saved_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, visible = false };
        saved_card.add_css_class ("cc-card");
        lists_box.append (saved_card);

        others_caption = new Gtk.Label ("OTHER NETWORKS") {
            xalign = 0, margin_start = 4, visible = false,
        };
        others_caption.add_css_class ("cc-caption");
        lists_box.append (others_caption);

        others_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true, visible = false };
        others_card.add_css_class ("cc-card");
        lists_box.append (others_card);

        content.append (make_list_scroll (lists_box));
        content.append (empty_label);

        build_pass_card ();
        content.append (pass_card);
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

        // Shown for saved networks alongside Connect/Disconnect: drops the
        // NetworkManager profile so the network reverts to "other".
        forget_btn = new Gtk.Button.with_label ("Forget") {
            valign = Gtk.Align.CENTER, visible = false,
        };
        forget_btn.add_css_class ("lumen-button");
        forget_btn.clicked.connect (do_forget);
        row.append (forget_btn);

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
        return selected_key != "" && selected_key == service.connected_ssid;
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
        int idx = index_of (selected_key);
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

    void do_forget () {
        int idx = index_of (selected_key);
        if (idx < 0) return;
        service.forget (sorted_nets[idx].ssid);
        close_password_panel ();
    }

    void close_password_panel () {
        clear_selection ();
        error_ssid = ""; error_msg = "";
        password_field.text = "";
        reveal_btn.active = false;
        password_field.obscure_text = true;
        password_field.blur ();
        set_status ("", false);
        pass_card.visible = false;
    }

    void select_ssid (string ssid, bool reset_input) {
        select_key (ssid);
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

    // Idempotent — safe to call after every rebuild.
    void update_password_panel () {
        int idx = index_of (selected_key);
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
        forget_btn.visible     = net.is_saved && !connecting;
        forget_btn.sensitive   = !connecting;

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
        if (ssid != selected_key) return;

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
        string previous = selected_key;
        rebuild_rows ();

        if (previous != "" && index_of (previous) < 0
            && previous != service.connecting_ssid) {
            close_password_panel ();
        } else if (previous != "") {
            select_ssid (previous, false);
        }

        update_view ();
    }

    void rebuild_rows () {
        Gtk.Widget? w;
        while ((w = conn_card.get_first_child ()) != null)   conn_card.remove (w);
        while ((w = saved_card.get_first_child ()) != null)  saved_card.remove (w);
        while ((w = others_card.get_first_child ()) != null) others_card.remove (w);
        rows.clear ();

        var connected = new Gee.ArrayList<WifiNet> ();
        var saved     = new Gee.ArrayList<WifiNet> ();
        var others    = new Gee.ArrayList<WifiNet> ();
        foreach (var net in service.nets) {
            if (net.ssid == service.connected_ssid) connected.add (net);
            else if (net.is_saved)                  saved.add (net);
            else                                    others.add (net);
        }
        CompareDataFunc<WifiNet> by_signal = (a, b) => b.signal - a.signal;
        saved.sort (by_signal);
        others.sort (by_signal);

        // Flatten in display order so index_of()/selection stays consistent.
        var ordered = new Gee.ArrayList<WifiNet> ();
        ordered.add_all (connected);
        ordered.add_all (saved);
        ordered.add_all (others);
        sorted_nets = ordered.to_array ();

        foreach (var net in connected)
            append_row (net, true, conn_card, false);

        for (int i = 0; i < saved.size; i++)
            append_row (saved[i], false, saved_card, i < saved.size - 1);

        for (int i = 0; i < others.size; i++)
            append_row (others[i], false, others_card, i < others.size - 1);
    }

    void append_row (WifiNet net, bool connected, Gtk.Box card, bool separator) {
        var row = new WifiRow (net, connected);
        row.show_separator = separator;
        string captured_ssid = net.ssid;
        row.activated.connect (() => {
            if (selected_key == captured_ssid) close_password_panel ();
            else                               select_ssid (captured_ssid, true);
        });
        rows.add (row);
        card.append (row);
    }

    void update_view () {
        sync_header (service.enabled, service.scanning);

        bool has_conn = service.connected_ssid != "" && service.connected_ssid != "--";
        int  saved_n  = 0;
        int  others_n = 0;
        foreach (var net in sorted_nets) {
            if (net.ssid == service.connected_ssid) continue;
            if (net.is_saved) saved_n++;
            else              others_n++;
        }

        conn_card.visible = has_conn;

        // Caption a section only when there's another card it needs to be told
        // apart from (a connected card above, or the sibling saved/other card).
        saved_card.visible     = saved_n > 0;
        saved_caption.visible  = saved_n > 0 && (has_conn || others_n > 0);
        others_card.visible    = others_n > 0;
        others_caption.visible = others_n > 0 && (has_conn || saved_n > 0);
        list_scroll.visible    = saved_n > 0 || others_n > 0;

        if (!service.enabled) {
            set_empty ("Wi-Fi is off");
            list_scroll.visible = false;
            saved_caption.visible = false;
            others_caption.visible = false;
        } else if (rows.size == 0) {
            set_empty (service.scanning ? "Scanning…" : "No networks found");
        } else {
            set_empty ("");
        }
    }
}
