using Gtk;

// Page-bearing tray icon. Each icon owns a Gtk.Widget to show when the tray
// is expanded with that icon active. Implementors register with TrayBar
// via add_paged().
public interface IPagedTrayItem : GLib.Object {
    public abstract Gtk.Widget icon_widget ();
    public abstract Gtk.Widget page_widget ();
}

// Right-aligned tray. Visual model matches the original DrawKit panel:
// a single rounded rectangle anchored at the bottom-right of the panel
// whose top edge grows upward when a paged icon is activated. The icon
// row sits at the TOP of the expanded rectangle; the active page fills
// the area BELOW the icons but still above the screen edge. Clicking
// the active icon again collapses the rectangle back to the icon row.
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

        // Order matters: icon row first so it sits at the TOP of the box;
        // the revealer is the LAST child so its content occupies the BOTTOM.
        // The whole box is bottom-anchored in the layer-shell window, so as
        // the revealer expands the icon row gets pushed upward — matching
        // the original behavior of the bg rectangle growing up while keeping
        // the icons at the top of that rectangle.
        icon_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.CENTER,
        };
        icon_row.add_css_class("tray-icons");
        append(icon_row);

        page_stack = new Gtk.Stack() {
            transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            transition_duration = 220,
            hhomogeneous = true,
            vhomogeneous = true,
            hexpand = true,
            vexpand = true,
        };

        revealer = new Gtk.Revealer() {
            // SLIDE_DOWN: content slides in from the top of the revealer's
            // area, which is just below the icon row — visually the page
            // "drops" out from under the icons as the tray expands.
            transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
            transition_duration = 280,
            reveal_child = false,
            child = page_stack,
        };
        revealer.add_css_class("tray-pages");
        append(revealer);
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
