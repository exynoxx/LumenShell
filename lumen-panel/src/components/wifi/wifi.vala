using Gtk;

public class WifiTray : GLib.Object, ITrayApplet, IControlModule {
    WifiService service;
    TrayButton icon;
    WifiModule module_tile;
    WifiDetail detail;

    public WifiTray () {
        service = new WifiService ();
        icon = new TrayButton ("nowifi");
        module_tile = new WifiModule (service);
        detail = new WifiDetail (service);
        module_tile.tile ().activated.connect (() => open_detail ());

        service.state_changed.connect (update_icon);
        service.refresh_scan (false);
    }

    void update_icon () {
        string name;
        if      (service.connected)          name = "wifi";
        else if (service.ethernet_connected) name = "ethernet";
        else                                  name = "nowifi";
        icon.set_icon_from_resource (name);
    }

    public Gtk.Widget tray_widget () { return icon; }

    public string module_id () { return "wifi"; }
    public Gtk.Widget  home_tile ()   { return module_tile.tile (); }
    public Gtk.Widget? detail_view () { return detail; }
}
