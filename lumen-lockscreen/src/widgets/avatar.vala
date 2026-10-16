// Owns its Picture's layout because Picture's natural size is the image's (the
// fallback SVG is 1024px). overflow=HIDDEN: border-radius doesn't clip children.
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
            pic = new Gtk.Picture.for_filename(icon_path);
            pic.content_fit = Gtk.ContentFit.COVER;
            inset = 0;
        } else {
            pic = new Gtk.Picture.for_resource(
                "/org/lumenshell/lockscreen/res/default-avatar.svg");
            pic.content_fit = Gtk.ContentFit.CONTAIN;
            inset = (int) (size * 0.22);
        }
        pic.can_shrink = true;
        pic.set_parent(this);
    }

    protected override void measure(Gtk.Orientation orientation, int for_size,
                                    out int minimum, out int natural,
                                    out int minimum_baseline,
                                    out int natural_baseline) {
        minimum = natural = Theme.avatar_size;
        minimum_baseline = natural_baseline = -1;
    }

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
