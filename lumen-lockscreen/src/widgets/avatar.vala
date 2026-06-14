using Gtk;

// Round user avatar. Loads the AccountsService / ~/.face icon resolved by
// AccountsClient; falls back to a bundled default profile picture
// (res/default-avatar.svg) when none is available.
// The image is COVER-fit and the widget clips to a circle: CSS border-radius
// only paints rounded corners — it does NOT clip child content — so we also set
// overflow = HIDDEN, which clips the child Picture to the rounded silhouette.
public class AvatarWidget : Gtk.Box {

    public AvatarWidget(string icon_path) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        set_halign(Gtk.Align.CENTER);
        set_valign(Gtk.Align.CENTER);
        add_css_class("lockscreen-avatar");
        set_overflow(Gtk.Overflow.HIDDEN);

        int size = Theme.avatar_size;
        set_size_request(size, size);

        Gtk.Picture pic;
        bool have_user = icon_path != "" && FileUtils.test(icon_path, FileTest.EXISTS);
        if (have_user) {
            // Real user photo: fill the whole circle.
            pic = new Gtk.Picture.for_filename(icon_path);
            pic.content_fit = Gtk.ContentFit.COVER;
            pic.set_size_request(size, size);
        } else {
            // Bundled illustrated bust: inset it so it sits inside the circle
            // with breathing room rather than cropping edge-to-edge.
            pic = new Gtk.Picture.for_resource(
                "/org/lumenshell/lockscreen/res/default-avatar.svg");
            pic.content_fit = Gtk.ContentFit.CONTAIN;
            int inset = (int) (size * 0.22);
            pic.margin_top = inset;
            pic.margin_bottom = inset;
            pic.margin_start = inset;
            pic.margin_end = inset;
            pic.set_size_request(size - 2 * inset, size - 2 * inset);
        }
        // FILL (not CENTER): the picture must take exactly the allocation we
        // give it so content_fit scales the image DOWN into `size`. With CENTER
        // a Gtk.Picture is allocated its image's intrinsic resolution (e.g. the
        // 512×512 viewBox of default-avatar.svg), which is what made the avatar
        // render far larger than `size`.
        pic.halign = Gtk.Align.FILL;
        pic.valign = Gtk.Align.FILL;
        append(pic);
    }

    // Hard-cap the widget's size. set_size_request is only a MINIMUM, and a
    // Gtk.Box reports a natural size as large as its child's natural size — so
    // the child Picture's intrinsic image resolution would otherwise propagate
    // up and the centered parent in window.vala would allocate that huge size.
    // Returning a fixed natural size makes the avatar exactly `avatar-size` px.
    protected override void measure(Gtk.Orientation orientation, int for_size,
                                    out int minimum, out int natural,
                                    out int minimum_baseline,
                                    out int natural_baseline) {
        minimum = natural = Theme.avatar_size;
        minimum_baseline = natural_baseline = -1;
    }
}
