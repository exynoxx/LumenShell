using Gtk;

// BluetoothPage — full-panel Bluetooth manager, mirroring WifiPage.
//
// Layout:
//   [Title  Scan  Power   ...   ConnectionChip]   ← header (44 px)
//   ──────────── 1 px separator ─────────────
//   [ BluetoothRow ... ]                           ← scrolled list (custom rows)
//   ──────────── 1 px separator ─────────────
//   [ <device name>        Connect/Disconnect/Pair ] ← action bar (54 px),
//                                                      only shown when a row
//                                                      is selected
public class BluetoothPage : Gtk.Box {

    const int PAD      = 14;
    const int HEADER_H = 44;
    const int ACTION_H = 54;

    BluetoothService service;

    Gtk.Label  title_label;
    Gtk.Button scan_btn;
    Gtk.Switch power_switch;
    LumenChip  conn_chip;
    bool       syncing_power = false;

    Gtk.ScrolledWindow scroll;
    Gtk.Box list_box;

    Gtk.Box    action_bar;
    Gtk.Label  name_label;
    Gtk.Button action_btn;

    Gee.ArrayList<BluetoothRow> rows = new Gee.ArrayList<BluetoothRow>();
    BtDevice[] shown = {};
    int selected_index = -1;

    static Gdk.RGBA chip_online  = Utils.rgba(0.18f, 0.88f, 0.42f, 1f);
    static Gdk.RGBA chip_offline = Utils.rgba(0.52f, 0.52f, 0.57f, 1f);

    public BluetoothPage (BluetoothService service) {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.service = service;
        add_css_class("wifi-page");
        set_size_request(380, 320);

        build_header();
        append(build_separator());
        build_list();
        append(build_separator());
        build_action_bar();

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

        title_label = new Gtk.Label("Bluetooth") {
            xalign = 0,
            valign = Gtk.Align.CENTER,
        };
        title_label.add_css_class("page-title");
        header.append(title_label);

        scan_btn = new Gtk.Button.with_label("Scan") {
            valign = Gtk.Align.CENTER,
        };
        scan_btn.add_css_class("lumen-button");
        scan_btn.clicked.connect(() => service.refresh_scan(true));
        header.append(scan_btn);

        power_switch = new Gtk.Switch() {
            valign = Gtk.Align.CENTER,
        };
        power_switch.add_css_class("lumen-switch");
        // Guard against the programmatic sync in update_header() looping back
        // into set_power(); only user toggles should drive the adapter.
        power_switch.notify["active"].connect(() => {
            if (syncing_power) return;
            service.set_power(power_switch.active);
        });
        header.append(power_switch);

        var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true };
        header.append(spacer);

        conn_chip = new LumenChip() { valign = Gtk.Align.CENTER };
        header.append(conn_chip);

        append(header);
        update_header();
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

    void build_action_bar () {
        action_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
            height_request = ACTION_H,
            margin_start = PAD,
            margin_end = PAD,
            visible = false,
        };

        name_label = new Gtk.Label("") {
            xalign = 0,
            valign = Gtk.Align.CENTER,
            hexpand = true,
            ellipsize = Pango.EllipsizeMode.END,
        };
        name_label.add_css_class("connected-label");
        action_bar.append(name_label);

        action_btn = new Gtk.Button.with_label("Connect") {
            valign = Gtk.Align.CENTER,
            width_request = 110,
        };
        action_btn.add_css_class("lumen-button");
        action_btn.clicked.connect(do_action);
        action_bar.append(action_btn);

        append(action_bar);
    }

    BtDevice? selected_device () {
        if (selected_index < 0 || selected_index >= shown.length) return null;
        return shown[selected_index];
    }

    void do_action () {
        var dev = selected_device();
        if (dev == null) return;
        if      (dev.connected) service.disconnect_device(dev.mac);
        else if (dev.paired)    service.connect_device(dev.mac);
        else                    service.pair_device(dev.mac);
        close_action_bar();
    }

    void close_action_bar () {
        selected_index = -1;
        foreach (var r in rows) r.selected = false;
        action_bar.visible = false;
        queue_draw();
    }

    void select_row (int i) {
        if (i < 0 || i >= rows.size) return;
        for (int j = 0; j < rows.size; j++) rows[j].selected = (j == i);
        selected_index = i;

        var dev = selected_device();
        if (dev == null) return;

        name_label.label = dev.name;
        if (dev.connected) {
            action_btn.label = "Disconnect";
            action_btn.add_css_class("danger");
        } else {
            action_btn.label = dev.paired ? "Connect" : "Pair";
            action_btn.remove_css_class("danger");
        }
        action_bar.visible = true;
    }

    void on_service_changed () {
        string prev_mac = "";
        if (selected_index >= 0 && selected_index < rows.size)
            prev_mac = rows[selected_index].mac;

        rebuild_rows();
        scan_btn.label = service.scanning ? "Scanning" : "Scan";
        update_header();

        if (prev_mac != "") {
            int found = -1;
            for (int i = 0; i < rows.size; i++) {
                if (rows[i].mac == prev_mac) { found = i; break; }
            }
            if (found >= 0) select_row(found);
            else            close_action_bar();
        }
    }

    void rebuild_rows () {
        Gtk.Widget? w;
        while ((w = list_box.get_first_child()) != null) list_box.remove(w);
        rows.clear();

        shown = sorted_devices();
        foreach (var dev in shown) {
            var row = new BluetoothRow(dev);
            int captured_index = rows.size;
            row.activated.connect(() => {
                if (selected_index == captured_index) close_action_bar();
                else                                    select_row(captured_index);
            });
            row.disconnect_clicked.connect(() => service.disconnect_device(dev.mac));
            rows.add(row);
            list_box.append(row);
        }
    }

    // Connected first, then paired, then discovered — each group keeps the
    // bluetoothctl order.
    BtDevice[] sorted_devices () {
        BtDevice[] connected = {};
        BtDevice[] paired    = {};
        BtDevice[] other     = {};
        foreach (var d in service.devices) {
            if      (d.connected) connected += d;
            else if (d.paired)    paired    += d;
            else                  other     += d;
        }
        BtDevice[] result = {};
        foreach (var d in connected) result += d;
        foreach (var d in paired)    result += d;
        foreach (var d in other)     result += d;
        return result;
    }

    void update_header () {
        if (power_switch.active != service.powered) {
            syncing_power = true;
            power_switch.active = service.powered;
            syncing_power = false;
        }

        string dev = service.connected_name;
        bool online = dev != "";
        conn_chip.set_text(online ? "●  " + dev
                                   : (service.powered ? "●  No device" : "●  Off"));
        conn_chip.set_text_color(online ? chip_online : chip_offline);
    }
}
