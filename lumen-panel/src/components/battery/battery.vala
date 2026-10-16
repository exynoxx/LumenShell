public class BatteryTray : GLib.Object, ITrayApplet, IControlModule {
    BatteryService service;
    TrayButton icon;
    BatteryModule module_tile;

    public BatteryTray (BatteryService service, PowerProfileService power_profiles) {
        this.service = service;
        icon = new TrayButton ("nobattery");
        module_tile = new BatteryModule (service, power_profiles);

        service.state_changed.connect (update_icon);
        update_icon ();
    }

    void update_icon () {
        icon.set_icon_from_resource (service.icon_name ());
    }

    public Gtk.Widget tray_widget () { return icon; }

    public string module_id () { return "battery"; }
    public Gtk.Widget  home_tile ()   { return module_tile.tile (); }
    public Gtk.Widget? detail_view () { return null; }
}
