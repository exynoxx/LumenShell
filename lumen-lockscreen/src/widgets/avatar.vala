using Gtk;

// Round user avatar. Loads the AccountsService / ~/.face icon resolved by
// AccountsClient; falls back to a bundled default profile picture
// (res/default-avatar.svg) when none is available.
//
// The image is COVER-fit (photo) or CONTAIN-fit (illustrated fallback) and the
// widget clips to a circle: CSS border-radius only paints rounded corners — it
// does NOT clip child content — so we also set overflow = HIDDEN, which clips
// the child Picture to the rounded silhouette.
//
// This is a bare Gtk.Widget (not a Gtk.Box) that fully owns the layout of its
// single Picture child. That matters because Gtk.Picture's natural size is the
// intrinsic resolution of its image. The fallback SVG is authored at 1024px so
// it rasterises crisply at HiDPI; if the Picture's natural size were allowed to
// drive layout, the avatar would balloon to ~1024px. By pinning measure() to
// avatar-size and allocating the child ourselves, the rendered size is always
// exactly avatar-size regardless of the source image's resolution.
public class AvatarWidget : Gtk.Widget {

    private Gtk.Picture pic;
    private int inset;   // breathing room for the illustrated fallback; 0 for a real photo

    public AvatarWidget(string icon_path) {
        add_css_class("lockscreen-avatar");
        set_overflow(Gtk.Overflow.HIDDEN);
        set_halign(Gtk.Align.CENTER);
        set_valign(Gtk.Align.CENTER);

        int size = Theme.avatar_size;

        bool have_user = icon_path != "" && FileUtils.test(icon_path, FileTest.EXISTS);
        if (have_user) {
            // Real user photo: fill the whole circle, edge to edge.
            pic = new Gtk.Picture.for_filename(icon_path);
            pic.content_fit = Gtk.ContentFit.COVER;
            inset = 0;
        } else {
            // Bundled illustrated bust: inset it so it sits inside the circle
            // with breathing room rather than cropping edge-to-edge.
            pic = new Gtk.Picture.for_resource(
                "/org/lumenshell/lockscreen/res/default-avatar.svg");
            pic.content_fit = Gtk.ContentFit.CONTAIN;
            inset = (int) (size * 0.22);
        }
        pic.can_shrink = true;
        pic.set_parent(this);
    }

    // Always exactly avatar-size square, independent of the child Picture's
    // intrinsic image resolution.
    protected override void measure(Gtk.Orientation orientation, int for_size,
                                    out int minimum, out int natural,
                                    out int minimum_baseline,
                                    out int natural_baseline) {
        minimum = natural = Theme.avatar_size;
        minimum_baseline = natural_baseline = -1;
    }

    // Allocate the Picture inside our box, inset for the illustrated fallback.
    protected override void size_allocate(int width, int height, int baseline) {
        int w = int.max(0, width  - 2 * inset);
        int h = int.max(0, height - 2 * inset);
        pic.allocate(w, h, -1, new Gsk.Transform().translate({ (float) inset, (float) inset }));
    }

    protected override void snapshot(Gtk.Snapshot snapshot) {
        snapshot_child(pic, snapshot);
    }

    public override void dispose() {
        if (pic != null) {
            pic.unparent();
            pic = null;
        }
        base.dispose();
    }
}
