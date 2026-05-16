/* PoC: GTK4 + gtk4-layer-shell + GSK panel that lists open toplevels via
 * zwlr-foreign-toplevel-management-unstable-v1 bound onto GDK's wl_display.
 *
 * Demonstrates:
 *   1. gdk_wayland_display_get_wl_display() returns a real wl_display
 *      (proves the symbol exists and works from Vala).
 *   2. We can bind extra Wayland protocols on the SAME wl_display that GTK
 *      is using, and the events fire on GTK's main loop with no extra
 *      dispatch glue.
 *   3. gtk4-layer-shell positions the window as a bottom panel.
 */

using Gtk;

class Panel : Object {

    Gtk.ListBox  list;
    GLib.HashTable<uint, Gtk.ListBoxRow> rows = new GLib.HashTable<uint, Gtk.ListBoxRow>(direct_hash, direct_equal);

    public void build (Gtk.Application app) {
        var win = new Gtk.ApplicationWindow(app);

        /* layer-shell: bottom panel, 60px exclusive, anchored L/R/B */
        GtkLayerShell.init_for_window(win);
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_namespace(win, "lumen-poc");
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT,   true);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT,  true);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_exclusive_zone(win, 60);
        GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE);

        list = new Gtk.ListBox() { selection_mode = Gtk.SelectionMode.NONE };
        list.add_css_class("navigation-sidebar");

        var scroll = new Gtk.ScrolledWindow() {
            child = list,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
            height_request    = 60,
        };
        win.set_child(scroll);

        var css = new Gtk.CssProvider();
        css.load_from_string("""
            window      { background: alpha(black, 0.55); color: white; }
            row         { padding: 6px 12px; margin: 2px 4px; border-radius: 8px; }
            row:hover   { background: alpha(white, 0.10); }
            row.active  { background: alpha(white, 0.20); }
            label.app   { font-weight: 600; }
            label.title { opacity: 0.75; }
        """);
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        win.present();

        /* Gdk.Display is available as soon as the app has activated; bind now. */
        bind_toplevel_protocol();
    }

    void bind_toplevel_protocol () {
        var gdk_display = Gdk.Display.get_default();
        if (!(gdk_display is Gdk.Wayland.Display)) {
            stderr.printf("Not on Wayland — aborting toplevel binding.\n");
            return;
        }
        unowned Wl.Display wl_display = ((Gdk.Wayland.Display) gdk_display).get_wl_display();
        stdout.printf("got wl_display=%p from GTK\n", wl_display);

        int rc = ToplevelShim.init(
            wl_display,
            (ToplevelShim.AddedCb)   on_added,
            (ToplevelShim.ChangedCb) on_changed,
            (ToplevelShim.ClosedCb)  on_closed,
            this);
        if (rc != 0) { stderr.printf("toplevel_shim_init failed\n"); return; }

        ToplevelShim.finish_setup(wl_display);
    }

    /* C callbacks → static; route to instance via `user` */

    static void on_added (ToplevelShim.Entry *e, void *user) {
        var self = (Panel) user;
        Idle.add(() => { self.upsert_row(e->id, e->app_id, e->title, e->activated); return false; });
    }
    static void on_changed (ToplevelShim.Entry *e, void *user) {
        var self = (Panel) user;
        Idle.add(() => { self.upsert_row(e->id, e->app_id, e->title, e->activated); return false; });
    }
    static void on_closed (uint32 id, void *user) {
        var self = (Panel) user;
        Idle.add(() => { self.remove_row(id); return false; });
    }

    void upsert_row (uint id, string? app_id, string? title, bool activated) {
        var existing = rows.lookup(id);
        if (existing != null) {
            update_row(existing, app_id, title, activated);
            return;
        }
        var row = new Gtk.ListBoxRow();
        update_row(row, app_id, title, activated);
        list.append(row);
        rows.insert(id, row);
        stdout.printf("+ toplevel %u  app=%s  title=%s%s\n",
            id, app_id ?? "?", title ?? "?", activated ? "  [active]" : "");
    }

    void update_row (Gtk.ListBoxRow row, string? app_id, string? title, bool activated) {
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        var app_lbl = new Gtk.Label(app_id ?? "(no app_id)") { xalign = 0 };
        app_lbl.add_css_class("app");
        var ttl_lbl = new Gtk.Label(title ?? "") {
            xalign = 0,
            ellipsize = Pango.EllipsizeMode.END,
            hexpand = true,
        };
        ttl_lbl.add_css_class("title");
        box.append(app_lbl);
        box.append(ttl_lbl);
        row.set_child(box);
        if (activated) row.add_css_class("active"); else row.remove_css_class("active");
    }

    void remove_row (uint id) {
        var row = rows.lookup(id);
        if (row != null) { list.remove(row); rows.remove(id); }
        stdout.printf("- toplevel %u\n", id);
    }
}

int main (string[] args) {
    var app = new Gtk.Application("dev.lumen.poc.gtk4toplevel", GLib.ApplicationFlags.DEFAULT_FLAGS);
    var panel = new Panel();
    app.activate.connect(() => { panel.build(app); });
    return app.run(args);
}
