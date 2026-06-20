using Gtk;

public class BatteryTray : GLib.Object, ITrayApplet {
    BatteryService service;
    PowerProfileService power_profiles;
    TrayButton icon;
    BatteryPage page;

    public BatteryTray () {
        service = new BatteryService();
        power_profiles = new PowerProfileService();
        icon = new TrayButton("nobattery");
        page = new BatteryPage(service, power_profiles);

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

    public Gtk.Widget  tray_widget () { return icon; }
    public Gtk.Widget? detail_page () { return page; }
}
