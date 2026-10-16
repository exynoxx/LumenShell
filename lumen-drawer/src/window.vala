private const string DRAWER_CSS = """
    window.lumen-drawer-root {
        background: transparent;
        color: white;
    }

    .search-row {
        margin-top: 50px;
        margin-bottom: 30px;
    }

    .drawer-search {
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
    .drawer-search:focus,
    .drawer-search:focus-within {
        border: none;
        outline: none;
        box-shadow: none;
    }
    .drawer-search > text,
    .drawer-search > image {
        background: transparent;
        border: none;
        outline: none;
        box-shadow: none;
    }
    .drawer-search > text {
        color: black;
    }
    /* stock icon grey is nearly invisible on the white pill */
    .drawer-search > image {
        color: alpha(black, 0.55);
    }
    .drawer-search > image:first-child {
        margin-right: 6px;
    }
    .drawer-search > image:last-child {
        color: alpha(black, 0.45);
        border-radius: 11px;
        padding: 3px;
    }
    .drawer-search > image:last-child:hover {
        color: black;
        background: alpha(black, 0.10);
    }
    .drawer-search > text > placeholder {
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

    .drawer-hint {
        color: alpha(white, 0.22);
        font-size: 13pt;
        text-shadow: 0 1px 2px alpha(black, 0.4);
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

public class DrawerWindow : Gtk.ApplicationWindow {

    private AppEntry[] apps;
    private SearchDb search_db;

    private Gtk.SearchEntry search_entry;
    private Gtk.Stack body_stack;
    private PagedGrid grid;
    private SearchResults results;
    private PageDots dots;

    public DrawerWindow(Gtk.Application app, Gdk.Monitor? monitor = null) {
        Object(application: app);

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-drawer");
        if (monitor != null) GtkLayerShell.set_monitor(this, monitor);
        // BOTTOM, not BACKGROUND: wf-background lives on BACKGROUND and tends
        // to map after us, which would hide the grid.
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.BOTTOM);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,   true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT,  true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP,    true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_exclusive_zone(this, 0);
        // ON_DEMAND is load-bearing: NONE kills the search bar, and EXCLUSIVE
        // is silently ignored below the shell layer.
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);

        decorated = false;
        add_css_class("lumen-drawer-root");

        load_apps();
        search_db = new SearchDb(apps);

        build_ui();
        install_css();
        install_key_controller();

        map.connect(() => {
            search_entry.grab_focus();
            sync_keyboard_mode();
        });

        DrawerToplevels.instance.focus_changed.connect((any) => {
            // Grid is now hidden; reset so it never reopens mid-search.
            if (any) reset_view();
            sync_keyboard_mode();
        });
    }

    // The compositor hands keys back to this surface when no toplevel is
    // focused; keep the search entry as the GTK-side target so typing lands there.
    private void sync_keyboard_mode() {
        if (!DrawerToplevels.instance.any_focused) {
            search_entry.grab_focus();
        }
    }

    private void load_apps() {
        var list = new GenericArray<AppEntry>();
        foreach (var info in AppInfo.get_all()) {
            if (!info.should_show()) continue;
            var entry = new AppEntry(info);
            entry.launched.connect(() => {
                reset_view();
                LumenCommon.WayfireIpc.send_method("lumen-peek/stop");
            });
            list.add(entry);
        }
        list.sort((a, b) => GLib.strcmp(a.name, b.name));
        apps = new AppEntry[list.length];
        for (int i = 0; i < list.length; i++) apps[i] = list[i];
        stdout.printf("lumen-drawer: %d apps\n", apps.length);
    }

    private void reset_view() {
        search_entry.set_text("");
        grid.reset_to_first_page();
        body_stack.set_visible_child_name("grid");
        dots.set_visible(grid.page_count > 1);
    }

    // SearchDb must be rebuilt too: it holds an *unowned* alias of the old apps[].
    public void reload() {
        load_apps();
        search_db = new SearchDb(apps);

        body_stack.remove(grid);
        grid = new PagedGrid(apps);
        body_stack.add_named(grid, "grid");
        grid.page_changed.connect((p) => dots.set_active(p));

        dots.set_count(grid.page_count);
        reset_view();
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
        search_entry.add_css_class("drawer-search");
        search_entry.set_placeholder_text("Search");
        // Stock edit-clear-symbolic knocks the x out of a blob: invisible on
        // the white pill, so swap in the stroked x.
        var clear_icon = search_entry.get_last_child() as Gtk.Image;
        if (clear_icon != null) clear_icon.set_from_icon_name("window-close-symbolic");
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

        // Overlay keeps the hint out of the grid's layout so tiles never shift.
        var overlay = new Gtk.Overlay();
        overlay.set_child(root);

        var hint = new Gtk.Label("Ctrl + click an app to run it as administrator") {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.END,
            margin_bottom = 90,
        };
        hint.add_css_class("drawer-hint");
        overlay.add_overlay(hint);

        set_child(overlay);
    }

    private static bool css_installed = false;
    private static void install_css() {
        if (css_installed) return;
        css_installed = true;
        var css = new Gtk.CssProvider();
        css.load_from_string(DRAWER_CSS);
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    private void install_key_controller() {
        // CAPTURE, or the focused search entry swallows Left/Right for caret
        // motion; printable keys still fall through to it.
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
                reset_view();
                LumenCommon.WayfireIpc.send_method("lumen-peek/stop");
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
