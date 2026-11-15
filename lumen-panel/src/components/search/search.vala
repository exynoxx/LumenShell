// Magnifier button: spawns `lumen-search --toggle`. Claims the press so the
// tray row's own click handler doesn't also open the Control Center.
public class SearchTray : GLib.Object, ITrayApplet {
    TrayButton icon;

    public SearchTray () {
        icon = new TrayButton ("search");
        icon.add_css_class ("tray-search");
        var click = new Gtk.GestureClick () { button = Gdk.BUTTON_PRIMARY };
        click.pressed.connect (() => click.set_state (Gtk.EventSequenceState.CLAIMED));
        click.released.connect (() => LumenCommon.Proc.spawn_detached ({ "lumen-search", "--toggle" }));
        icon.add_controller (click);
    }

    public Gtk.Widget tray_widget () { return icon; }
}
