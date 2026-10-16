public const int ICON_SIZE = 96;

public class AppTile : Gtk.Button {

    public AppEntry? entry { get; private set; }

    private Gtk.Image image;
    private Gtk.Label label;

    public AppTile() {
        add_css_class("app-tile");
        add_css_class("flat");

        // Centred so the homogeneous Grid never stretches the tile.
        set_halign(Gtk.Align.CENTER);
        set_valign(Gtk.Align.CENTER);

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        box.set_halign(Gtk.Align.CENTER);

        image = new Gtk.Image();
        image.pixel_size = ICON_SIZE;
        image.set_halign(Gtk.Align.CENTER);

        label = new Gtk.Label("");
        label.set_ellipsize(Pango.EllipsizeMode.END);
        label.set_max_width_chars(20);
        label.set_halign(Gtk.Align.CENTER);

        box.append(image);
        box.append(label);
        set_child(box);

        clicked.connect(() => {
            if (entry == null) return;
            // Live modifier state: Gtk.Button consumes the press internally.
            if (ctrl_held()) entry.launch_as_root();
            else             entry.launch();
        });
    }

    private static bool ctrl_held() {
        var dpy = Gdk.Display.get_default();
        if (dpy == null) return false;
        var seat = dpy.get_default_seat();
        if (seat == null) return false;
        var kb = seat.get_keyboard();
        if (kb == null) return false;
        return (kb.get_modifier_state() & Gdk.ModifierType.CONTROL_MASK) != 0;
    }

    public void bind(AppEntry e) {
        // Skip rebinds: set_from_gicon does an icon-theme lookup per call.
        if (this.entry == e) return;
        this.entry = e;
        label.set_text(e.short_name);
        var gicon = e.info.get_icon();
        if (gicon != null) {
            image.set_from_gicon(gicon);
        } else {
            image.set_from_icon_name("application-x-executable");
        }
    }

    public void unbind() {
        if (this.entry == null) return;
        this.entry = null;
        image.clear();
        label.set_text("");
    }
}
