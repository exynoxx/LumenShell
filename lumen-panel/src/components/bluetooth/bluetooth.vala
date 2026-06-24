using Gtk;

public class BluetoothTray : GLib.Object, ITrayApplet, IControlModule {
    BluetoothService service;
    TrayButton icon;
    BluetoothModule module_tile;
    BluetoothDetail detail;

    public BluetoothTray () {
        service = new BluetoothService ();
        icon = new TrayButton ("bluetooth-off");
        module_tile = new BluetoothModule (service);
        detail = new BluetoothDetail (service);
        module_tile.tile ().activated.connect (() => open_detail ());

        service.state_changed.connect (update_icon);
        service.refresh_scan (false);
    }

    void update_icon () {
        string name;
        if      (!service.powered)  name = "bluetooth-off";
        else if (service.connected) name = "bluetooth-connected";
        else                         name = "bluetooth";
        icon.set_icon_from_resource (name);
    }

    public Gtk.Widget tray_widget () { return icon; }

    public string module_id () { return "bluetooth"; }
    public Gtk.Widget  home_tile ()   { return module_tile.tile (); }
    public Gtk.Widget? detail_view () { return detail; }
}
