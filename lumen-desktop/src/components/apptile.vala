public const int ICON_SIZE = 96;
public const int TILE_LABEL_FONT_PT = 11;

public class AppTile : Gtk.Button {

    public AppEntry? entry { get; private set; }

    private Gtk.Image image;
    private Gtk.Label label;

    public AppTile() {
        add_css_class("app-tile");
        // strip default button chrome; CSS provides hover/active backgrounds
        add_css_class("flat");

        // Center the tile within its cell so a homogeneous Grid can spread
        // cells across the page without stretching individual tiles.
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
            // Ctrl held at click → launch as administrator (pkexec). We query
            // the live keyboard modifier state rather than a press-time gesture
            // because Gtk.Button consumes the click internally; the seat's
            // keyboard still reports Ctrl as held through the release.
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
        // Skip when this tile is already showing the same entry — search
        // results often keep tile[0] = firefox across "fi" → "fir" → "fire",
        // and Gtk.Image.set_from_gicon triggers icon-theme lookup each call.
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
