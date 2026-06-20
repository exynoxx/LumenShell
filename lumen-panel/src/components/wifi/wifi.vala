using Gtk;

public class WifiTray : GLib.Object, ITrayApplet {
    WifiService service;
    TrayButton icon;
    WifiPage page;

    public WifiTray () {
        service = new WifiService();
        icon = new TrayButton("nowifi");
        page = new WifiPage(service);

        service.state_changed.connect(update_icon);
        service.refresh_scan(false);
    }

    void update_icon () {
        string name;
        if      (service.connected)          name = "wifi";
        else if (service.ethernet_connected) name = "ethernet";
        else                                  name = "nowifi";
        icon.set_icon_from_resource(name);
    }

    public Gtk.Widget  tray_widget () { return icon; }
    public Gtk.Widget? detail_page () { return page; }
}
