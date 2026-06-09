using Gtk;

// Page-bearing tray icon. Each icon owns a Gtk.Button to show when the tray
// is expanded with that icon active. Implementors register with TrayBar
// via add_paged().
public interface IPagedTrayItem : GLib.Object {
    public abstract Gtk.Button icon_widget ();
    public abstract Gtk.Widget page_widget ();
}

// Right-aligned tray. Visual model matches the original DrawKit panel:
// a single rounded rectangle anchored at the bottom-right of the panel
// whose top edge grows upward when a paged icon is activated. The icon
// row sits at the TOP of the expanded rectangle; the active page fills
// the area BELOW the icons but still above the screen edge.
//
// Interactions:
//   - Click a paged icon → its page slides in; the tray expands.
//   - Click the currently-active icon → tray collapses.
//   - Click another paged icon while expanded → the page-stack crossfades/
//     slides to the new page (direction follows icon order in the stack).
//   - ESC anywhere on the panel → tray collapses (wired by main.vala via
//     the public collapse() entry point).
public class TrayBar : Gtk.Box {

    Gtk.Box icon_row;
    public Gtk.Revealer revealer { get; private set; }
    Gtk.Stack page_stack;

    // Per-paged-icon bookkeeping so we can toggle the .active CSS class on
    // the right icon as the active page changes.
    GLib.HashTable<string, Gtk.Widget> icon_by_page =
        new GLib.HashTable<string, Gtk.Widget>(str_hash, str_equal);
    // Keeps IPagedTrayItem instances alive. Vala connects signal handlers
    // with g_signal_connect_object (weak ref to the handler's instance),
    // so without an owning reference here the item is freed as soon as
    // add_paged returns and its update_icon handler is auto-disconnected.
    Gee.ArrayList<IPagedTrayItem> paged_items = new Gee.ArrayList<IPagedTrayItem>();
    string? active_page_id = null;
    int next_page_id = 0;

    public signal void expanded_changed (bool expanded);

    public TrayBar () {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class("tray-bar");
        halign = Gtk.Align.END;
        // Bottom panel: bar anchored bottom-right, grows upward as a page
        // reveals. Top panel: anchored top-right, grows downward — same child
        // order (icon row first, revealer below), the revealer's SLIDE_DOWN
        // now opens away from the screen edge. The .at-top class flips the
        // floating margin from the bottom edge to the top.
        valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END;
        if (PanelConfig.at_top) add_css_class("at-top");
        // Clip children to the .tray-bar's rounded background so the page-
        // slide and reveal animations can't render past the corners.
        overflow = Gtk.Overflow.HIDDEN;

        // Order matters: icon row first so it sits at the TOP of the box;
        // the revealer is the LAST child so its content occupies the BOTTOM.
        // The whole box is bottom-anchored in the layer-shell window, so as
        // the revealer expands the icon row gets pushed upward.
        icon_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.CENTER,
        };
        icon_row.add_css_class("tray-icons");
        append(icon_row);

        page_stack = new Gtk.Stack() {
            // SLIDE_LEFT_RIGHT chooses direction from the relative order of
            // children: jumping to a later-added child slides left (new
            // content enters from the right) and vice versa.
            transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            transition_duration = 240,
            hhomogeneous = true,
            vhomogeneous = true,
            hexpand = true,
            vexpand = true,
        };

        revealer = new Gtk.Revealer() {
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

        paged_items.add(item);
        var icon = item.icon_widget();
        icon_row.append(icon);
        icon_by_page.insert(id, icon);
        page_stack.add_named(item.page_widget(), id);
        icon.clicked.connect(() => toggle(id));
    }

    void toggle (string id) {
        if (active_page_id == id) {
            collapse();
            return;
        }
        // Clear previous icon's active state; mark the new one.
        if (active_page_id != null) {
            var prev = icon_by_page.lookup(active_page_id);
            if (prev != null) prev.remove_css_class("active");
        }
        var next = icon_by_page.lookup(id);
        if (next != null) next.add_css_class("active");

        page_stack.visible_child_name = id;
        bool was_open = (active_page_id != null);
        active_page_id = id;
        if (!was_open) {
            revealer.reveal_child = true;
            expanded_changed(true);
        }
    }

    public void collapse () {
        if (active_page_id == null) return;
        var prev = icon_by_page.lookup(active_page_id);
        if (prev != null) prev.remove_css_class("active");
        active_page_id = null;
        revealer.reveal_child = false;
        expanded_changed(false);
    }

    public bool is_expanded () { return active_page_id != null; }
}
