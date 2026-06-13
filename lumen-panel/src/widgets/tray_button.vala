using Gtk;

public class TrayButton : Gtk.Button {

    Gtk.Image image;

    public signal void primary_pressed ();

    public TrayButton (string icon_resource_name) {
        add_css_class("tray-icon");
        image = new Gtk.Image() {
            pixel_size = 22,
        };
        set_icon_from_resource(icon_resource_name);
        set_child(image);
        clicked.connect(() => primary_pressed());
    }

    public void set_icon_from_resource (string name) {
        image.set_from_resource("/dev/lumen/panel/icons/" + name + ".svg");
    }

    public void set_active_visual (bool active) {
        if (active) add_css_class("active"); else remove_css_class("active");
    }
}
