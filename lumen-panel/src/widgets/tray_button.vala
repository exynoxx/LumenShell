// Passive status icon: the whole TrayBar is one click target. A Box wrapper
// because GtkImage is final.
public class TrayButton : Gtk.Box {

    Gtk.Image image;
    string?   current = null;

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

    // Services re-emit state_changed for unrelated fields; reloading the SVG
    // would re-parse, re-rasterise and queue_resize every time.
    public void set_icon_from_resource (string name) {
        if (name == current) return;
        current = name;
        image.set_from_resource ("/dev/lumen/panel/icons/" + name + ".svg");
    }
}
