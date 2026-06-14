using Gtk;

// LockBackdrop — the frosted backdrop behind the lock card. The blurred image
// is precomputed and cached by BlurredWallpaper, so this widget just paints it
// cover-fit under a scrim tint — the macOS lock look. Falls back to the raw
// (unblurred) theme background image, then a solid scrim, when no blurred
// texture is available.
public class LockBackdrop : Gtk.Widget {

    private Gtk.Picture pic;

    public LockBackdrop(Gdk.Texture? blurred) {
        layout_manager = new Gtk.BinLayout();
        add_css_class("lockscreen-backdrop");

        pic = new Gtk.Picture() {
            content_fit = Gtk.ContentFit.COVER,
            hexpand = true,
            vexpand = true,
        };
        if (blurred != null) {
            pic.set_paintable(blurred);
        } else if (Theme.background_image != ""
                   && FileUtils.test(Theme.background_image, FileTest.EXISTS)) {
            pic.file = File.new_for_path(Theme.background_image);
        }
        pic.set_parent(this);
    }

    ~LockBackdrop() {
        if (pic != null) pic.unparent();
    }

    public override void snapshot(Gtk.Snapshot s) {
        int w = get_width();
        int h = get_height();

        Graphene.Rect bounds = {};
        bounds.init(0, 0, (float) w, (float) h);

        // The texture is already blurred (BlurredWallpaper); paint it as-is.
        snapshot_child(pic, s);

        s.append_color(Theme.scrim, bounds);
    }
}
