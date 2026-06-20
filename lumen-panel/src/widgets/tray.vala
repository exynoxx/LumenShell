using Gtk;

// Unified tray-applet contract. A tray widget always goes in the icon row;
// items that also have a detail page (WiFi, Bluetooth, …) return it from
// detail_page() and get paged-reveal wiring. Icon-only items (Clock, SysTray)
// return null.
public interface ITrayApplet : GLib.Object {
    public abstract Gtk.Widget  tray_widget ();   // goes in the icon row
    public abstract Gtk.Widget? detail_page ();   // null = icon-only (clock, systray)
}

public class TrayBar : Gtk.Box {

    Gtk.Box icon_row;
    public Gtk.Revealer revealer { get; private set; }
    Gtk.Stack page_stack;

    GLib.HashTable<string, Gtk.Widget> icon_by_page =
        new GLib.HashTable<string, Gtk.Widget>(str_hash, str_equal);
    // Keeps ITrayApplet instances alive. Vala connects signal handlers
    // with g_signal_connect_object (weak ref to the handler's instance),
    // so without an owning reference here the item is freed as soon as
    // add returns and its update_icon handler is auto-disconnected.
    Gee.ArrayList<ITrayApplet> applets = new Gee.ArrayList<ITrayApplet>();
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

    // Append an applet's tray widget to the icon row. When the applet has a
    // detail page AND its tray widget is a button (the only thing that can
    // toggle a reveal), register the page and wire the click to toggle it.
    public void add (ITrayApplet item) {
        applets.add(item);
        var w = item.tray_widget();
        icon_row.append(w);
        var page = item.detail_page();
        if (page != null && w is Gtk.Button) {
            string id = "page-%d".printf(next_page_id++);
            icon_by_page.insert(id, w);
            page_stack.add_named(page, id);
            ((Gtk.Button) w).clicked.connect(() => toggle(id));
        }
    }

    void toggle (string id) {
        if (active_page_id == id) {
            collapse();
            return;
        }
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
