using Gtk;

// Page-bearing tray icon. Each icon owns a Gtk.Widget to show when the tray
// is expanded with that icon active. Implementors register with TrayBar
// via add_page_item().
public interface IPagedTrayItem : GLib.Object {
    public abstract Gtk.Widget icon_widget ();
    public abstract Gtk.Widget page_widget ();
}

// Right-aligned row of tray icons sitting in the bottom 60 px. When an
// IPagedTrayItem is clicked, a Revealer above the icon row expands to host
// that item's page widget. Clicking the active icon again, or any other
// page-bearing icon, switches/closes the page.
public class TrayBar : Gtk.Box {

    Gtk.Box icon_row;
    public Gtk.Revealer revealer { get; private set; }
    Gtk.Stack page_stack;
    GLib.HashTable<string, IPagedTrayItem> pages =
        new GLib.HashTable<string, IPagedTrayItem>(str_hash, str_equal);
    string? active_page_id = null;
    int next_page_id = 0;

    public TrayBar () {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class("tray-bar");
        halign = Gtk.Align.END;
        valign = Gtk.Align.END;

        page_stack = new Gtk.Stack() {
            transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            transition_duration = 220,
            hhomogeneous = true,
            vhomogeneous = true,
            hexpand = true,
            vexpand = true,
        };

        revealer = new Gtk.Revealer() {
            transition_type = Gtk.RevealerTransitionType.SLIDE_UP,
            transition_duration = 280,
            reveal_child = false,
            child = page_stack,
        };
        revealer.add_css_class("tray-pages");
        append(revealer);

        icon_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.CENTER,
        };
        icon_row.add_css_class("tray");
        append(icon_row);
    }

    // Add a leaf icon (no page). E.g. Clock, Exit.
    public void add_icon (Gtk.Widget icon_w) {
        icon_row.append(icon_w);
    }

    // Add a page-bearing icon. Clicking the icon toggles its page.
    public void add_paged (IPagedTrayItem item) {
        string id = "page-%d".printf(next_page_id++);
        pages.insert(id, item);

        var icon = item.icon_widget();
        icon_row.append(icon);
        page_stack.add_named(item.page_widget(), id);

        // Reuse Gtk.Button's clicked signal if the icon is a Button; otherwise
        // attach a GestureClick.
        if (icon is Gtk.Button) {
            ((Gtk.Button) icon).clicked.connect(() => toggle(id));
        } else {
            var click = new Gtk.GestureClick();
            click.released.connect(() => toggle(id));
            icon.add_controller(click);
        }
    }

    void toggle (string id) {
        if (active_page_id == id) {
            collapse();
        } else {
            page_stack.visible_child_name = id;
            active_page_id = id;
            revealer.reveal_child = true;
        }
    }

    public void collapse () {
        active_page_id = null;
        revealer.reveal_child = false;
    }
}
