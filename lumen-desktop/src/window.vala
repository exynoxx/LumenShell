using Gtk;

private const string DESKTOP_CSS = """
    window.lumen-desktop-root {
        background: transparent;
        color: white;
    }

    .search-row {
        margin-top: 50px;
        margin-bottom: 30px;
    }

    .desktop-search {
        min-width: 250px;
        min-height: 30px;
        background: alpha(white, 0.85);
        color: black;
        border: none;
        outline: none;
        box-shadow: none;
        border-radius: 20px;
        padding: 2px 8px;
    }
    .desktop-search:focus,
    .desktop-search:focus-within {
        border: none;
        outline: none;
        box-shadow: none;
    }
    .desktop-search > text,
    .desktop-search > image {
        background: transparent;
        border: none;
        outline: none;
        box-shadow: none;
    }
    .desktop-search > text {
        color: black;
    }
    .desktop-search > text > placeholder {
        color: alpha(black, 0.55);
    }

    .app-tile {
        background: transparent;
        border: none;
        box-shadow: none;
        border-radius: 15px;
        padding: 8px;
        color: white;
    }
    .app-tile:hover {
        background: alpha(white, 0.30);
    }
    .app-tile:active {
        background: alpha(#333, 0.70);
    }
    .app-tile label {
        color: white;
        font-size: 11pt;
    }

    .page-dots {
        margin-bottom: 30px;
    }
    .page-dot {
        min-width: 26px;
        min-height: 26px;
        padding: 2px;
        border-radius: 15px;
        background: #4d4d4d;
        color: white;
        border: none;
        box-shadow: none;
        transition: background 120ms ease-out;
    }
    .page-dot:hover {
        background: #6a6a6a;
    }
    .page-dot:active {
        background: #222;
    }
    .page-dot.active {
        background: white;
        color: black;
    }
    .page-dot.active:hover {
        background: alpha(white, 0.85);
    }
    .page-dot.active:active {
        background: alpha(white, 0.65);
    }
""";

public class DesktopWindow : Gtk.ApplicationWindow {

    private AppEntry[] apps;
    private SearchDb search_db;

    private Gtk.SearchEntry search_entry;
    private Gtk.Stack body_stack;
    private PagedGrid grid;
    private SearchResults results;
    private PageDots dots;

    // Only the focus-owner window (primary monitor) takes keyboard focus. With
    // several lumen-desktop surfaces sharing one namespace, more than one
    // grabbing focus would fight wayfire-default-focus, so secondaries are
    // built with KeyboardMode.NONE and never grab the search entry.
    private bool focus_owner;

    public DesktopWindow(Gtk.Application app, Gdk.Monitor? monitor = null,
                         bool focus_owner = true) {
        Object(application: app);
        this.focus_owner = focus_owner;

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-desktop");
        if (monitor != null) GtkLayerShell.set_monitor(this, monitor);
        // BOTTOM (not BACKGROUND) so we stack ABOVE wf-shell's wf-background
        // wallpaper surface — wf-background also lives on BACKGROUND and
        // tends to map after us, hiding us. BOTTOM still renders below all
        // regular app windows, so the "closing apps re-exposes the tile
        // grid" property is preserved.
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.BOTTOM);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,   true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT,  true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP,    true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
        // 0 = do not consume an exclusive zone; foreground windows ignore
        // our presence when sizing. Distinct from Kickoff's -1 (which forces
        // full-output coverage at the cost of overlapping other layers).
        GtkLayerShell.set_exclusive_zone(this, 0);
        // ON_DEMAND is the only legal keyboard mode for a BOTTOM-layer
        // surface — wlr-layer-shell forbids EXCLUSIVE below the shell
        // layer (it is silently ignored). Auto-handing the keyboard back
        // to us when no toplevel is focused is therefore implemented on
        // the compositor side: wayfire-curtain-peek focuses this surface
        // when it reveals the grid, and wayfire-default-focus keeps focus
        // here whenever no toplevel holds it.
        GtkLayerShell.set_keyboard_mode(this,
            focus_owner ? GtkLayerShell.KeyboardMode.ON_DEMAND
                        : GtkLayerShell.KeyboardMode.NONE);

        decorated = false;
        add_css_class("lumen-desktop-root");

        load_apps();
        search_db = new SearchDb(apps);

        build_ui();
        install_css();
        install_key_controller();

        map.connect(() => {
            if (!focus_owner) return;
            search_entry.grab_focus();
            sync_keyboard_mode();
        });

        DesktopToplevels.instance.focus_changed.connect((any) => {
            sync_keyboard_mode();
        });
    }

    // The compositor hands keyboard focus back to our layer surface whenever
    // no toplevel is focused (wayfire-curtain-peek on reveal, then
    // wayfire-default-focus thereafter). Make sure the search entry is the
    // GTK-side focus target so the keys land there and not on some other
    // widget that happened to be last-focused.
    private void sync_keyboard_mode() {
        if (!focus_owner) return;
        if (!DesktopToplevels.instance.any_focused) {
            search_entry.grab_focus();
        }
    }

    private void load_apps() {
        var list = new Gee.ArrayList<AppEntry>();
        foreach (var info in AppInfo.get_all()) {
            if (!info.should_show()) continue;
            var entry = new AppEntry(info);
            // Dispatching an app closes the curtain over the grid so the new
            // window is revealed as the doors swing shut. Also reset transient
            // UI state (query + page) so the drawer doesn't reopen later in a
            // filtered/paginated state.
            entry.launched.connect(() => {
                reset_view();
                LumenDesktop.CurtainIpc.close();
            });
            list.add(entry);
        }
        list.sort((a, b) => GLib.strcmp(a.name, b.name));
        apps = new AppEntry[list.size];
        for (int i = 0; i < list.size; i++) apps[i] = list[i];
        stdout.printf("lumen-desktop: %d apps\n", apps.length);
    }

    private void reset_view() {
        search_entry.set_text("");
        grid.reset_to_first_page();
        body_stack.set_visible_child_name("grid");
        dots.set_visible(grid.page_count > 1);
    }

    private void build_ui() {
        var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        root.set_halign(Gtk.Align.FILL);
        root.set_valign(Gtk.Align.FILL);
        root.set_hexpand(true);
        root.set_vexpand(true);

        var search_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        search_row.add_css_class("search-row");
        search_row.set_halign(Gtk.Align.CENTER);

        search_entry = new Gtk.SearchEntry();
        search_entry.add_css_class("desktop-search");
        search_entry.set_placeholder_text("Search");
        search_entry.set_size_request(320, -1);
        search_entry.set_hexpand(false);
        search_entry.set_halign(Gtk.Align.CENTER);
        search_entry.search_changed.connect(on_search_changed);
        search_entry.activate.connect(on_search_activate);
        search_row.append(search_entry);
        root.append(search_row);

        body_stack = new Gtk.Stack();
        body_stack.set_transition_type(Gtk.StackTransitionType.NONE);
        body_stack.set_hexpand(true);
        body_stack.set_vexpand(true);

        grid = new PagedGrid(apps);
        body_stack.add_named(grid, "grid");

        results = new SearchResults();
        body_stack.add_named(results, "results");

        body_stack.set_visible_child_name("grid");
        root.append(body_stack);

        dots = new PageDots(grid.page_count);
        grid.page_changed.connect((p) => dots.set_active(p));
        dots.page_clicked.connect((p) => grid.goto_page(p));
        root.append(dots);

        set_child(root);
    }

    private static bool css_installed = false;
    private static void install_css() {
        if (css_installed) return;
        css_installed = true;
        var css = new Gtk.CssProvider();
        css.load_from_string(DESKTOP_CSS);
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    private void install_key_controller() {
        // CAPTURE phase: the search entry has focus the moment the desktop is
        // clicked, and it would otherwise swallow Left/Right for caret motion
        // before our handler ever sees them. Capturing first lets us claim
        // arrow keys for page navigation while still returning false for
        // printable keys, so typing falls through to the SearchEntry and
        // populates the query as expected.
        var key = new Gtk.EventControllerKey();
        key.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        key.key_pressed.connect(on_key_pressed);
        ((Gtk.Widget) this).add_controller(key);
    }

    private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
        var mods = state & (Gdk.ModifierType.CONTROL_MASK
                          | Gdk.ModifierType.ALT_MASK
                          | Gdk.ModifierType.SHIFT_MASK
                          | Gdk.ModifierType.SUPER_MASK);

        switch (keyval) {
            case Gdk.Key.Escape:
                // Close the curtain over the grid, hiding the desktop again.
                LumenDesktop.CurtainIpc.close();
                return true;
            case Gdk.Key.Left:
                if (!search_db.active && mods == 0) { grid.prev_page(); return true; }
                return false;
            case Gdk.Key.Right:
                if (!search_db.active && mods == 0) { grid.next_page(); return true; }
                return false;
            case Gdk.Key.@1:
            case Gdk.Key.KP_1:
                if (search_db.active && mods == Gdk.ModifierType.ALT_MASK)
                    return results.launch_at(0);
                return false;
            case Gdk.Key.@2:
            case Gdk.Key.KP_2:
                if (search_db.active && mods == Gdk.ModifierType.ALT_MASK)
                    return results.launch_at(1);
                return false;
            case Gdk.Key.@3:
            case Gdk.Key.KP_3:
                if (search_db.active && mods == Gdk.ModifierType.ALT_MASK)
                    return results.launch_at(2);
                return false;
            case Gdk.Key.BackSpace:
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    search_entry.set_text("");
                    return true;
                }
                return false;
            default:
                return false;
        }
    }

    private void on_search_changed() {
        sync_query();
    }

    private void on_search_activate() {
        sync_query();
        if (search_db.active) {
            results.launch_first();
        }
    }

    private void sync_query() {
        var text = search_entry.get_text();
        search_db.set_query(text);
        if (search_db.active) {
            results.update(search_db.filtered, search_db.size);
            body_stack.set_visible_child_name("results");
            dots.set_visible(false);
        } else {
            body_stack.set_visible_child_name("grid");
            dots.set_visible(grid.page_count > 1);
        }
    }
}
