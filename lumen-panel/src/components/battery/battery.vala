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
        service.refresh();

        // poll every 10s to keep status fresh
        GLib.Timeout.add_seconds(10, () => {
            service.refresh();
            return Source.CONTINUE;
        });
    }

    void update_icon () {
        string name;
        var raw = service.raw_status;
        if (raw == "charging") name = "charging";
        else if (raw == "discharging" || raw.contains("full")) {
            var p = service.percent;
            name = p >= 70 ? "high" : p >= 30 ? "mid" : "low";
        } else name = "nobattery";
        icon.set_icon_from_resource(name);
    }

    public Gtk.Widget icon_widget () { return icon; }
    public Gtk.Widget page_widget () { return page; }
}
