using Gtk;

public class BluetoothTray : GLib.Object, IPagedTrayItem {
    BluetoothService service;
    TrayButton icon;
    BluetoothPage page;

    public BluetoothTray () {
        service = new BluetoothService();
        icon = new TrayButton("bluetooth-off");
        page = new BluetoothPage(service);

        service.state_changed.connect(update_icon);
        service.refresh_scan(false);
    }

    void update_icon () {
        string name;
        if      (!service.powered)  name = "bluetooth-off";
        else if (service.connected) name = "bluetooth-connected";
        else                         name = "bluetooth";
        icon.set_icon_from_resource(name);
    }

    public Gtk.Button icon_widget () { return icon; }
    public Gtk.Widget page_widget () { return page; }
}
