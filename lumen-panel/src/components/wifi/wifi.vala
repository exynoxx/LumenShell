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
        if (!service.connected) {
            icon.set_icon_from_resource("nowifi");
            return;
        }
        // Pick strength based on the connected SSID's current signal.
        int sig = 0;
        foreach (var n in service.nets) {
            if (n.ssid == service.connected_ssid) { sig = n.signal; break; }
        }
        icon.set_icon_from_resource(sig >= 60 ? "wifi" : sig > 0 ? "wifi-unknown" : "wifi");
    }

    public Gtk.Widget icon_widget () { return icon; }
    public Gtk.Widget page_widget () { return page; }
}
