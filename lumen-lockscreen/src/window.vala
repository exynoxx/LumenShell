using Gtk;

// One lock surface. NOT a layer-shell window — gtk4-session-lock turns it into
// an ext_session_lock_surface_v1 via assign_window_to_monitor()+present() (done
// by LockManager). The compositor sizes it to fill its output, so we only build
// centered content. The primary surface carries the auth card; secondary
// outputs show clock + wallpaper only.
public class LockWindow : Gtk.ApplicationWindow {

    public bool is_primary { get; private set; }
    public PasswordField? password = null;   // non-null only on the primary

    public LockWindow(Gtk.Application app, bool is_primary,
                      AccountsClient.UserInfo user, LogindBridge logind) {
        Object(application: app);
        this.is_primary = is_primary;

        decorated = false;
        add_css_class("lockscreen-root");

        var bg = new Gtk.Picture() {
            content_fit = Gtk.ContentFit.COVER,
            hexpand = true,
            vexpand = true,
        };
        if (Theme.background_image != ""
            && FileUtils.test(Theme.background_image, FileTest.EXISTS)) {
            bg.file = File.new_for_path(Theme.background_image);
        }

        var center = new Gtk.Box(Gtk.Orientation.VERTICAL, 22) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };

        center.append(new ClockWidget());

        if (is_primary) {
            center.append(new AvatarWidget(user.icon_path));

            var name_label = new Gtk.Label(user.real_name) {
                halign = Gtk.Align.CENTER,
            };
            name_label.add_css_class("lockscreen-name");
            center.append(name_label);

            password = new PasswordField();
            center.append(password);

            if (Theme.show_power_menu)
                center.append(new PowerMenu(logind));
        }

        // Overlay the centered cluster on the (optional) wallpaper.
        var overlay = new Gtk.Overlay();
        overlay.set_child(bg);
        overlay.add_overlay(center);
        set_child(overlay);
    }
}
