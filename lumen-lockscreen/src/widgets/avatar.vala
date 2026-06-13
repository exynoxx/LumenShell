using Gtk;

// Round user avatar. Loads the AccountsService / ~/.face icon resolved by
// AccountsClient; falls back to a generic symbolic when none is available.
// Rounding is done in CSS (.lockscreen-avatar) so we stay on stock widgets.
public class AvatarWidget : Gtk.Box {

    public AvatarWidget(string icon_path) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        set_halign(Gtk.Align.CENTER);
        add_css_class("lockscreen-avatar");

        int size = Theme.avatar_size;
        set_size_request(size, size);

        Gtk.Widget img;
        if (icon_path != "" && FileUtils.test(icon_path, FileTest.EXISTS)) {
            var pic = new Gtk.Picture.for_filename(icon_path) {
                content_fit = Gtk.ContentFit.COVER,
                width_request = size,
                height_request = size,
            };
            img = pic;
        } else {
            var ph = new Gtk.Image.from_icon_name("avatar-default-symbolic") {
                pixel_size = (int) (size * 0.7),
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER,
            };
            ph.add_css_class("lockscreen-avatar-fallback");
            img = ph;
        }
        append(img);
    }
}
