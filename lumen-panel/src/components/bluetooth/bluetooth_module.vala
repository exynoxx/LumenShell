using Gtk;

// Overview tile for Bluetooth: round toggle (powers the adapter) + live
// subtitle + chevron into the device list.
public class BluetoothModule : GLib.Object {

    BluetoothService service;
    CcToggleRow row;

    public BluetoothModule (BluetoothService service) {
        this.service = service;
        row = new CcToggleRow ("Bluetooth", "bluetooth", "bluetooth-off", true);
        row.toggled.connect ((want) => service.set_power (want));
        service.state_changed.connect (update);
        update ();
    }

    public CcToggleRow tile () { return row; }

    void update () {
        row.set_on (service.powered);
        if (!service.powered)          row.set_subtitle ("Off");
        else if (service.connected)    row.set_subtitle (service.connected_name);
        else                           row.set_subtitle ("On");
    }
}
