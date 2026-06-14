using Gtk;

// LockBackdrop — the frosted backdrop behind the lock card. ext-session-lock
// blanks the real desktop, so the manager captures a snapshot just before
// locking; this widget renders it cover-fit under a heavy GSK blur plus a
// scrim tint — the macOS lock look. Falls back to the theme background image,
// then a solid scrim, when no snapshot is available.
public class LockBackdrop : Gtk.Widget {

    private Gtk.Picture pic;

    public LockBackdrop(Gdk.Texture? snapshot) {
        layout_manager = new Gtk.BinLayout();
        add_css_class("lockscreen-backdrop");

        pic = new Gtk.Picture() {
            content_fit = Gtk.ContentFit.COVER,
            hexpand = true,
            vexpand = true,
        };
        if (snapshot != null) {
            pic.set_paintable(snapshot);
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

        // Blur the snapshot child; pop restores normal compositing for the
        // scrim drawn on top.
        s.push_blur((double) Theme.blur_radius);
        snapshot_child(pic, s);
        s.pop();

        s.append_color(Theme.scrim, bounds);
    }
}
