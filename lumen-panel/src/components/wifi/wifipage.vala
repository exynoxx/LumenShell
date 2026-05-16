using Gtk;

// WifiPage — full-panel WiFi manager built from custom widgets to match the
// original DrawKit look (no GtkSearchEntry / GtkListBox chrome).
//
// Layout:
//   [Title  Refresh   ...   ConnectionChip]   ← header (44 px)
//   ──────────── 1 px separator ─────────────
//   [ WifiRow ... ]                            ← scrolled list (custom rows)
//   ──────────── 1 px separator ─────────────
//   [ LumenTextField    Connect/Disconnect ]   ← password panel (54 px),
//                                                only shown when a row is
//                                                selected
public class WifiPage : Gtk.Box {

    const int PAD          = 14;
    const int HEADER_H     = 44;
    const int PASS_H       = 54;

    WifiService service;

    Gtk.Label title_label;
    Gtk.Button refresh_btn;
    LumenChip conn_chip;

    Gtk.ScrolledWindow scroll;
    Gtk.Box list_box;

    Gtk.Box password_panel;
    LumenTextField password_field;
    Gtk.Button connect_btn;
    Gtk.Label  connected_label;

    Gee.ArrayList<WifiRow> rows = new Gee.ArrayList<WifiRow>();
    int selected_index = -1;

    static Gdk.RGBA chip_online  = Utils.rgba(0.18f, 0.88f, 0.42f, 1f);
    static Gdk.RGBA chip_offline = Utils.rgba(0.52f, 0.52f, 0.57f, 1f);

    public WifiPage (WifiService service) {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.service = service;
        add_css_class("wifi-page");
        set_size_request(380, 320);

        build_header();
        append(build_separator());
        build_list();
        append(build_separator());
        build_password_panel();

        service.state_changed.connect(on_service_changed);
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

        var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true };
        header.append(spacer);

        conn_chip = new LumenChip() { valign = Gtk.Align.CENTER };
        header.append(conn_chip);

        append(header);
        update_connection_chip();
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
        append(scroll);
    }

    void build_password_panel () {
        password_panel = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
            height_request = PASS_H,
            margin_start = PAD,
            margin_end = PAD,
            visible = false,
        };

        password_field = new LumenTextField() {
            placeholder = "Password…",
            obscure_text = true,
            hexpand = true,
            valign = Gtk.Align.CENTER,
        };
        password_field.submitted.connect(do_connect);
        password_field.cancelled.connect(close_password_panel);
        password_panel.append(password_field);

        connected_label = new Gtk.Label("Connected") {
            xalign = 0,
            valign = Gtk.Align.CENTER,
            hexpand = true,
            visible = false,
        };
        connected_label.add_css_class("connected-label");
        password_panel.append(connected_label);

        connect_btn = new Gtk.Button.with_label("Connect") {
            valign = Gtk.Align.CENTER,
            width_request = 100,
        };
        connect_btn.add_css_class("lumen-button");
        connect_btn.clicked.connect(() => {
            if (selected_is_connected()) do_disconnect();
            else                          do_connect();
        });
        password_panel.append(connect_btn);

        append(password_panel);
    }

    bool selected_is_connected () {
        if (selected_index < 0) return false;
        var nets = service.nets;
        return selected_index < nets.length
            && nets[selected_index].ssid == service.connected_ssid;
    }

    void do_connect () {
        var nets = service.nets;
        if (selected_index < 0 || selected_index >= nets.length) return;
        service.connect_to(nets[selected_index].ssid, password_field.text);
        close_password_panel();
    }

    void do_disconnect () {
        service.disconnect_active();
        close_password_panel();
    }

    void close_password_panel () {
        selected_index = -1;
        foreach (var r in rows) r.selected = false;
        password_field.text = "";
        password_field.blur();
        password_panel.visible = false;
        queue_draw();
    }

    void select_row (int i) {
        if (i < 0 || i >= rows.size) return;
        for (int j = 0; j < rows.size; j++) rows[j].selected = (j == i);
        selected_index = i;
        password_field.text = "";

        bool already_connected = selected_is_connected();
        password_field.visible = !already_connected;
        connected_label.visible = already_connected;
        connect_btn.label = already_connected ? "Disconnect" : "Connect";
        if (already_connected) connect_btn.add_css_class("danger");
        else                    connect_btn.remove_css_class("danger");

        password_panel.visible = true;
        if (!already_connected) password_field.grab_text_focus();
    }

    void on_service_changed () {
        string prev_ssid = "";
        if (selected_index >= 0 && selected_index < rows.size)
            prev_ssid = rows[selected_index].ssid;

        rebuild_rows();
        refresh_btn.label = service.scanning ? "Scanning" : "Refresh";

        if (prev_ssid != "") {
            int found = -1;
            for (int i = 0; i < rows.size; i++) {
                if (rows[i].ssid == prev_ssid) { found = i; break; }
            }
            if (found >= 0) select_row(found);
            else            close_password_panel();
        }

        update_connection_chip();
    }

    void rebuild_rows () {
        Gtk.Widget? w;
        while ((w = list_box.get_first_child()) != null) list_box.remove(w);
        rows.clear();

        foreach (var net in service.nets) {
            var row = new WifiRow(net, net.ssid == service.connected_ssid);
            int captured_index = rows.size;
            row.activated.connect(() => {
                if (selected_index == captured_index) close_password_panel();
                else                                    select_row(captured_index);
            });
            row.disconnect_clicked.connect(do_disconnect);
            rows.add(row);
            list_box.append(row);
        }
    }

    void update_connection_chip () {
        string ssid = service.connected_ssid;
        bool online = ssid != "" && ssid != "--";
        conn_chip.set_text(online ? "●  " + ssid : "●  Offline");
        conn_chip.set_text_color(online ? chip_online : chip_offline);
    }
}
