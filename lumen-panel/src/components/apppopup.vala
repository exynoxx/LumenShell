using Gtk;

// Right-click context menu for an AppEntry. Wraps Gtk.Popover with three
// buttons (Pin/Unpin, New window, Close windows). Edge-clamping is handled
// by GTK; on Wayfire with a bottom-anchored layer surface the popover
// extends upward correctly.
public class AppPopupMenu : Gtk.Popover {

    weak AppEntry entry;
    Gtk.Button pin_btn;
    Gtk.Button new_win_btn;
    Gtk.Button close_btn;
    Gtk.Label title_label;

    public AppPopupMenu (AppEntry entry) {
        this.entry = entry;
        add_css_class("app-popup");
        set_parent(entry);
        set_has_arrow(false);
        set_position(Gtk.PositionType.TOP);

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);

        title_label = new Gtk.Label(entry.display_name) {
            xalign = 0.5f,
            ellipsize = Pango.EllipsizeMode.END,
            max_width_chars = 24,
        };
        title_label.add_css_class("popup-title");
        box.append(title_label);

        box.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

        pin_btn = new Gtk.Button.with_label("Pin");
        pin_btn.clicked.connect(() => {
            entry.is_pinned = !entry.is_pinned;
            entry.pin_toggled();
            popdown();
        });
        box.append(pin_btn);

        new_win_btn = new Gtk.Button.with_label("New window");
        new_win_btn.clicked.connect(() => {
            entry.launch_new_window();
            popdown();
        });
        box.append(new_win_btn);

        close_btn = new Gtk.Button.with_label("Close windows");
        close_btn.clicked.connect(() => {
            entry.close_all_windows();
            popdown();
        });
        box.append(close_btn);

        set_child(box);
    }

    public void refresh () {
        title_label.label = entry.display_name;
        pin_btn.label = entry.is_pinned ? "Unpin" : "Pin";
        close_btn.sensitive = entry.has_open_windows();
    }
}
