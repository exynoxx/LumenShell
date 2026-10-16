using Gtk;

public class BluetoothDetail : CcListDetail {

    BluetoothService service;

    Gtk.Box list_card;

    Gtk.Box    action_card;
    Gtk.Label  name_label;
    Gtk.Button action_btn;

    BtDevice[] shown = {};

    public BluetoothDetail (BluetoothService service) {
        base ("Bluetooth", "cc-bluetooth-detail");
        this.service = service;

        build_content ();
        update_view ();

        service.state_changed.connect (on_service_changed);
        service.refresh_scan (false);
    }

    protected override void power_requested (bool on) { service.set_power (on); }
    protected override void refresh_requested ()      { service.refresh_scan (true); }

    void build_content () {
        list_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        list_card.add_css_class ("cc-card");
        content.append (make_list_scroll (list_card));
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
    }

    BtDevice? device_for (string mac) {
        foreach (var d in shown) if (d.mac == mac) return d;
        return null;
    }

    void do_action () {
        var dev = device_for (selected_key);
        if (dev == null) return;
        if      (dev.connected) service.disconnect_device (dev.mac);
        else if (dev.paired)    service.connect_device (dev.mac);
        else                    service.pair_device (dev.mac);
        close_action_bar ();
    }

    void close_action_bar () {
        clear_selection ();
        action_card.visible = false;
    }

    void select_device (string mac) {
        var dev = device_for (mac);
        if (dev == null) return;

        select_key (mac);

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
        string previous = selected_key;

        rebuild_rows ();
        update_view ();

        if (previous == "") return;
        if (has_key (previous)) select_device (previous);
        else                    close_action_bar ();
    }

    void rebuild_rows () {
        Gtk.Widget? w;
        while ((w = list_card.get_first_child ()) != null) list_card.remove (w);
        rows.clear ();

        shown = sorted_devices ();
        for (int i = 0; i < shown.length; i++) {
            var row = new BluetoothRow (shown[i]);
            row.show_separator = i < shown.length - 1;
            string captured_mac = shown[i].mac;
            row.activated.connect (() => {
                if (selected_key == captured_mac) close_action_bar ();
                else                              select_device (captured_mac);
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

    void update_view () {
        sync_header (service.powered, service.scanning);

        if (!service.powered) {
            set_empty ("Bluetooth is off");
            list_scroll.visible = false;
        } else if (rows.size == 0) {
            set_empty (service.scanning ? "Scanning…" : "No devices found");
            list_scroll.visible = false;
        } else {
            set_empty ("");
            list_scroll.visible = true;
        }
    }
}
