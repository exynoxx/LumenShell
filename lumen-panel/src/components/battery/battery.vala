using Gtk;

public class BatteryTray : GLib.Object, IPagedTrayItem {
    BatteryService service;
    TrayButton icon;
    BatteryPage page;

    public BatteryTray () {
        service = new BatteryService();
        icon = new TrayButton("nobattery");
        page = new BatteryPage(service);

        service.state_changed.connect(update_icon);
        update_icon();
    }

    void update_icon () {
        string name;
        var raw = service.raw_status;
        if (service.ac_online)                   name = "wired";
        else if (raw == "charging")              name = "charging";
        else if (raw == "discharging" || raw.contains("full")) {
            var p = service.percent;
            name = p >= 70 ? "high" : p >= 30 ? "mid" : "low";
        } else                                    name = "nobattery";
        icon.set_icon_from_resource(name);
    }

    public Gtk.Button icon_widget () { return icon; }
    public Gtk.Widget page_widget () { return page; }
}
