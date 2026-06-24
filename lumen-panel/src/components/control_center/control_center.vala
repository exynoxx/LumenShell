using Gtk;

// The single expanded panel (macOS Control Center). A wide rounded surface with
// an overview of round toggles + info tiles, and an internal stack that slides
// to a module's inline detail (Wi-Fi / Bluetooth network lists). The compact
// icon row above it is untouched — only this expanded area is new.
public class ControlCenter : Gtk.Box {

    const int WIDTH = 520;

    Gtk.Stack stack;
    Gtk.Box   home;
    GLib.HashTable<string, IControlModule> mods =
        new GLib.HashTable<string, IControlModule> (str_hash, str_equal);

    public ControlCenter (Gee.List<IControlModule> modules) {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class ("control-center");
        set_size_request (WIDTH, -1);

        foreach (var m in modules) mods.insert (m.module_id (), m);

        stack = new Gtk.Stack () {
            transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            transition_duration = 240,
            hhomogeneous = true,
            vhomogeneous = false,
            interpolate_size = true,
        };

        // Added directly (not wrapped in a ScrolledWindow): the overview is
        // short, and a ScrolledWindow's natural height doesn't propagate up to
        // the revealer, which collapsed the panel to a few px.
        home = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_start = 18, margin_end = 18, margin_top = 16, margin_bottom = 18,
        };
        stack.add_named (home, "home");

        build_home ();
        attach_details (modules);

        append (stack);
        stack.visible_child_name = "home";
    }

    void build_home () {
        // Connectivity card: Wi-Fi + Bluetooth toggle rows grouped together.
        var conn = new Gee.ArrayList<Gtk.Widget> ();
        add_toggle (conn, "wifi");
        add_toggle (conn, "bluetooth");
        if (conn.size > 0) home.append (make_card (conn));

        var sound = mods.lookup ("sound");
        if (sound != null) home.append (wrap_card (sound.home_tile ()));

        var battery = mods.lookup ("battery");
        if (battery != null) home.append (wrap_card (battery.home_tile ()));

        var power = mods.lookup ("exit");
        if (power != null) home.append (power.home_tile ());
    }

    void add_toggle (Gee.List<Gtk.Widget> into, string id) {
        var m = mods.lookup (id);
        if (m == null) return;
        var tile = m.home_tile ();
        var row = tile as CcToggleRow;
        if (row != null) row.activated.connect (() => open (id));
        into.add (tile);
    }

    void attach_details (Gee.List<IControlModule> modules) {
        foreach (var m in modules) {
            var d = m.detail_view ();
            if (d == null) continue;
            stack.add_named (d, "detail:" + m.module_id ());
            var cd = d as CcDetail;
            if (cd != null) cd.back_requested.connect (show_home);
        }
    }

    // Group rows into one rounded card with hairline separators between them.
    Gtk.Widget make_card (Gee.List<Gtk.Widget> rows) {
        var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        card.add_css_class ("cc-card");
        for (int i = 0; i < rows.size; i++) {
            if (i > 0) {
                var sep = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                    height_request = 1, margin_start = 58,
                };
                sep.add_css_class ("cc-row-sep");
                card.append (sep);
            }
            card.append (rows[i]);
        }
        return card;
    }

    Gtk.Widget wrap_card (Gtk.Widget child) {
        var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        card.add_css_class ("cc-card");
        card.append (child);
        return card;
    }

    // Open a module: slide to its detail if it has one, else stay on the
    // overview (where its tile lives inline).
    public void open (string id) {
        var m = mods.lookup (id);
        if (m != null && m.detail_view () != null)
            stack.visible_child_name = "detail:" + id;
        else
            show_home ();
    }

    public void show_home () {
        stack.visible_child_name = "home";
    }
}
