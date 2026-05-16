using Gtk;

public class WifiTray : GLib.Object, IPagedTrayItem {
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
        icon.set_icon_from_resource(service.connected ? "wifi" : "nowifi");
    }

    public Gtk.Widget icon_widget () { return icon; }
    public Gtk.Widget page_widget () { return page; }
}
