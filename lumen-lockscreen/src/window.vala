using Gtk;

// NOT layer-shell: gtk4-session-lock turns it into a lock surface when
// LockManager calls assign_window_to_monitor() + present().
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
            center.append(new ClockWidget());
        }

        var overlay = new Gtk.Overlay();
        overlay.set_child(new LockBackdrop(snapshot));
        overlay.add_overlay(center);

        // Separate overlay so it stays pinned to the bottom regardless of card height.
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
