using Gtk;

public class SoundTray : GLib.Object, ITrayApplet, IControlModule {
    SoundService service;
    TrayButton icon;
    SoundModule module_tile;
    SoundDetail detail;

    public SoundTray () {
        service = new SoundService ();
        icon = new TrayButton ("sound-max");
        module_tile = new SoundModule (service);
        detail = new SoundDetail (service);
        module_tile.open_requested.connect (() => open_detail ());

        service.state_changed.connect (update_icon);
        update_icon ();
    }

    void update_icon () {
        icon.set_icon_from_resource (service.muted ? "sound-mute" : "sound-max");
    }

    public Gtk.Widget tray_widget () { return icon; }

    public string module_id () { return "sound"; }
    public Gtk.Widget  home_tile ()   { return module_tile.tile (); }
    public Gtk.Widget? detail_view () { return detail; }
}
