using Gtk;

public class BatteryTray : GLib.Object, ITrayApplet, IControlModule {
    BatteryService service;
    PowerProfileService power_profiles;
    TrayButton icon;
    BatteryModule module_tile;

    public BatteryTray () {
        service = new BatteryService ();
        power_profiles = new PowerProfileService ();
        icon = new TrayButton ("nobattery");
        module_tile = new BatteryModule (service, power_profiles);

        service.state_changed.connect (update_icon);
        update_icon ();
    }

    void update_icon () {
        string name;
        var raw = service.raw_status;
        if (service.ac_online)                   name = "wired";
        else if (raw == "charging")              name = "charging";
        else if (raw == "discharging" || raw.contains ("full")) {
            var p = service.percent;
            name = p >= 70 ? "high" : p >= 30 ? "mid" : "low";
        } else                                    name = "nobattery";
        icon.set_icon_from_resource (name);
    }

    public Gtk.Widget tray_widget () { return icon; }

    public string module_id () { return "battery"; }
    public Gtk.Widget  home_tile ()   { return module_tile.tile (); }
    public Gtk.Widget? detail_view () { return null; }
}
