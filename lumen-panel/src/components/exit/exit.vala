using Gtk;

// Right-most tray item — expands a page offering session-end actions
// (log out, reboot, shutdown).
public class ExitTray : GLib.Object, IPagedTrayItem {
    TrayButton icon;
    ExitPage page;

    public ExitTray () {
        icon = new TrayButton("leaving");
        page = new ExitPage();
    }

    public Gtk.Button icon_widget () { return icon; }
    public Gtk.Widget page_widget () { return page; }
}
