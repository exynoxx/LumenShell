using Gtk;

public class SoundTray : GLib.Object, IPagedTrayItem {
    SoundService service;
    TrayButton icon;
    SoundPage page;

    public SoundTray () {
        service = new SoundService();
        icon = new TrayButton("sound-max");
        page = new SoundPage(service);

        service.state_changed.connect(update_icon);
        update_icon();
    }

    void update_icon () {
        icon.set_icon_from_resource(service.muted ? "sound-mute" : "sound-max");
    }

    public Gtk.Widget icon_widget () { return icon; }
    public Gtk.Widget page_widget () { return page; }
}
