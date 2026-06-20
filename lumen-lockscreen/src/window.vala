using Gtk;

// One lock surface. NOT a layer-shell window — gtk4-session-lock turns it into
// an ext_session_lock_surface_v1 via assign_window_to_monitor()+present() (done
// by LockManager). The compositor sizes it to fill its output. The primary
// surface carries the auth card (avatar + name + password, Apple-style);
// secondary outputs show the backdrop + clock only.
public class LockWindow : Gtk.ApplicationWindow {

    public bool is_primary { get; private set; }
    public PasswordField? password = null;   // non-null only on the primary

    public LockWindow(Gtk.Application app, bool is_primary,
                      AccountsClient.UserInfo user, LogindBridge logind,
                      Gdk.Texture? snapshot) {
        Object(application: app);
        this.is_primary = is_primary;

        decorated = false;
        add_css_class("lockscreen-root");

        // Centered cluster on top of the frosted backdrop.
        var center = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };

        if (is_primary) {
            center.append(new AvatarWidget(user.icon_path));

            var name_label = new Gtk.Label(user.real_name) {
                halign = Gtk.Align.CENTER,
            };
            name_label.add_css_class("lockscreen-name");
            center.append(name_label);

            password = new PasswordField();
            center.append(password);
        } else {
            // Secondary outputs: just the clock over the backdrop.
            center.append(new ClockWidget());
        }

        var overlay = new Gtk.Overlay();
        overlay.set_child(new LockBackdrop(snapshot));
        overlay.add_overlay(center);

        // Power actions hug the bottom edge (macOS-style), separate from the
        // centered auth cluster so they stay pinned regardless of card height.
        if (is_primary && Theme.show_power_menu) {
            var pm = new PowerMenu(logind) {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.END,
                margin_bottom = 48,
            };
            overlay.add_overlay(pm);
        }

        set_child(overlay);
    }
}
