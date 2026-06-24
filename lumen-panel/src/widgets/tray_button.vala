using Gtk;

// A status icon in the compact tray row. No longer a button: the whole tray
// bar is one click target (see TrayBar), so individual icons are passive and
// don't claim clicks. A Box wrapper (GtkImage is final and can't be subclassed)
// centers the icon and carries the .tray-icon chrome.
public class TrayButton : Gtk.Box {

    Gtk.Image image;

    public TrayButton (string icon_resource_name) {
        GLib.Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class ("tray-icon");
        image = new Gtk.Image () {
            pixel_size = 22,
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
            hexpand = true, vexpand = true,
        };
        append (image);
        set_icon_from_resource (icon_resource_name);
    }

    public void set_icon_from_resource (string name) {
        image.set_from_resource ("/dev/lumen/panel/icons/" + name + ".svg");
    }
}
