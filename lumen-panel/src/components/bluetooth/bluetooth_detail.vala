using Gtk;

// Inline Bluetooth detail: back header with power switch + scan spinner, a
// grouped device card (connected → paired → discovered), and a bottom action
// card (Connect / Disconnect / Pair) for the selected device. Selection logic
// carried over from the old BluetoothPage, keyed by MAC across rescans.
public class BluetoothDetail : CcDetail {

    BluetoothService service;

    Gtk.Switch  power_switch;
    Gtk.Button  scan_btn;
    Gtk.Spinner spinner;
    bool        syncing_power = false;

    Gtk.ScrolledWindow scroll;
    Gtk.Box   list_card;
    Gtk.Label empty_label;

    Gtk.Box    action_card;
    Gtk.Label  name_label;
    Gtk.Button action_btn;

    Gee.ArrayList<BluetoothRow> rows = new Gee.ArrayList<BluetoothRow> ();
    BtDevice[] shown = {};
    int selected_index = -1;

    public BluetoothDetail (BluetoothService service) {
        base ();
        this.service = service;
        add_css_class ("wifi-detail");

        build_header ();
        build_content ();
        update_header ();

        service.state_changed.connect (on_service_changed);
        service.refresh_scan (false);
    }

    void build_header () {
        var trailing = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { valign = Gtk.Align.CENTER };

        spinner = new Gtk.Spinner () { valign = Gtk.Align.CENTER, visible = false };
        trailing.append (spinner);

        scan_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        scan_btn.add_css_class ("cc-icon-btn");
        scan_btn.set_child (new Gtk.Label ("⟲"));
        scan_btn.clicked.connect (() => service.refresh_scan (true));
        trailing.append (scan_btn);

        power_switch = new Gtk.Switch () { valign = Gtk.Align.CENTER };
        power_switch.add_css_class ("lumen-switch");
        power_switch.notify["active"].connect (() => {
            if (syncing_power) return;
            service.set_power (power_switch.active);
        });
        trailing.append (power_switch);

        append (make_header ("Bluetooth", trailing));
    }

    void build_content () {
        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
            margin_start = 14, margin_end = 14, margin_bottom = 14, vexpand = true,
        };

        list_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        list_card.add_css_class ("cc-card");
        scroll = new Gtk.ScrolledWindow () {
            child = list_card,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
            vexpand = true,
            min_content_height = 200,
            max_content_height = 340,
            propagate_natural_height = true,
        };
        scroll.add_css_class ("cc-scroll");
        content.append (scroll);

        empty_label = new Gtk.Label ("") {
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
            vexpand = true, can_target = false, visible = false,
        };
        empty_label.add_css_class ("cc-empty");
        content.append (empty_label);

        action_card = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
            margin_start = 12, margin_end = 12, margin_top = 8, margin_bottom = 8,
            visible = false,
        };
        action_card.add_css_class ("cc-card");
        action_card.add_css_class ("cc-pass");
        name_label = new Gtk.Label ("") {
            xalign = 0, valign = Gtk.Align.CENTER, hexpand = true,
            ellipsize = Pango.EllipsizeMode.END,
        };
        name_label.add_css_class ("cc-row-title");
        action_card.append (name_label);
        action_btn = new Gtk.Button.with_label ("Connect") { valign = Gtk.Align.CENTER };
        action_btn.add_css_class ("lumen-button");
        action_btn.clicked.connect (do_action);
        action_card.append (action_btn);
        content.append (action_card);

        append (content);
    }

    BtDevice? selected_device () {
        if (selected_index < 0 || selected_index >= shown.length) return null;
        return shown[selected_index];
    }

    void do_action () {
        var dev = selected_device ();
        if (dev == null) return;
        if      (dev.connected) service.disconnect_device (dev.mac);
        else if (dev.paired)    service.connect_device (dev.mac);
        else                    service.pair_device (dev.mac);
        close_action_bar ();
    }

    void close_action_bar () {
        selected_index = -1;
        foreach (var r in rows) r.selected = false;
        action_card.visible = false;
    }

    void select_row (int i) {
        if (i < 0 || i >= rows.size) return;
        for (int j = 0; j < rows.size; j++) rows[j].selected = (j == i);
        selected_index = i;

        var dev = selected_device ();
        if (dev == null) return;

        name_label.label = dev.name;
        if (dev.connected) {
            action_btn.label = "Disconnect";
            action_btn.add_css_class ("danger");
        } else {
            action_btn.label = dev.paired ? "Connect" : "Pair";
            action_btn.remove_css_class ("danger");
        }
        action_card.visible = true;
    }

    void on_service_changed () {
        string prev_mac = "";
        if (selected_index >= 0 && selected_index < rows.size)
            prev_mac = rows[selected_index].mac;

        rebuild_rows ();
        update_header ();

        if (prev_mac != "") {
            int found = -1;
            for (int i = 0; i < rows.size; i++)
                if (rows[i].mac == prev_mac) { found = i; break; }
            if (found >= 0) select_row (found);
            else            close_action_bar ();
        }
    }

    void rebuild_rows () {
        Gtk.Widget? w;
        while ((w = list_card.get_first_child ()) != null) list_card.remove (w);
        rows.clear ();

        shown = sorted_devices ();
        for (int i = 0; i < shown.length; i++) {
            var dev = shown[i];
            var row = new BluetoothRow (dev);
            row.show_separator = i < shown.length - 1;
            int captured_index = i;
            row.activated.connect (() => {
                if (selected_index == captured_index) close_action_bar ();
                else                                  select_row (captured_index);
            });
            rows.add (row);
            list_card.append (row);
        }
    }

    // Connected → paired → discovered, each group keeping bluetoothctl order.
    BtDevice[] sorted_devices () {
        BtDevice[] result = {};
        foreach (var d in service.devices) if (d.connected) result += d;
        foreach (var d in service.devices) if (!d.connected && d.paired) result += d;
        foreach (var d in service.devices) if (!d.connected && !d.paired) result += d;
        return result;
    }

    void update_header () {
        if (power_switch.active != service.powered) {
            syncing_power = true;
            power_switch.active = service.powered;
            syncing_power = false;
        }
        scan_btn.sensitive = service.powered;
        scan_btn.visible   = !service.scanning;
        spinner.visible    = service.scanning;
        spinner.spinning   = service.scanning;

        if (!service.powered) {
            empty_label.label = "Bluetooth is off";
            empty_label.visible = true;
            scroll.visible = false;
        } else if (rows.size == 0) {
            empty_label.label = service.scanning ? "Scanning…" : "No devices found";
            empty_label.visible = true;
            scroll.visible = false;
        } else {
            empty_label.visible = false;
            scroll.visible = true;
        }
    }
}
