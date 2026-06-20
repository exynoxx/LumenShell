using Gtk;

public class ExitTray : GLib.Object, ITrayApplet {
    TrayButton icon;
    ExitPage page;

    public ExitTray (LogindBridge bridge) {
        icon = new TrayButton("leaving");
        page = new ExitPage(bridge);
    }

    public Gtk.Widget  tray_widget () { return icon; }
    public Gtk.Widget? detail_page () { return page; }
}
