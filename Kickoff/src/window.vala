using Gtk;

private const string KICKOFF_CSS = """
    window.kickoff-root {
        background: alpha(black, 0.8);
        color: white;
    }

    .search-row {
        margin-top: 50px;
        margin-bottom: 30px;
    }

    .kickoff-search {
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
    .kickoff-search:focus,
    .kickoff-search:focus-within {
        border: none;
        outline: none;
        box-shadow: none;
    }
    .kickoff-search > text,
    .kickoff-search > image {
        background: transparent;
        border: none;
        outline: none;
        box-shadow: none;
    }
    .kickoff-search > text {
        color: black;
    }
    .kickoff-search > text > placeholder {
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
    }
    .page-dot.active {
        background: white;
        color: black;
    }
""";

public class KickoffWindow : Gtk.ApplicationWindow {

    private AppEntry[] apps;
    private SearchDb search_db;

    private Gtk.SearchEntry search_entry;
    private Gtk.Stack body_stack;
    private PagedGrid grid;
    private SearchResults results;
    private PageDots dots;

    public KickoffWindow(Gtk.Application app) {
        Object(application: app);

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-kickoff");
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,   true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT,  true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP,    true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
        // -1 = extend the surface to the full output, ignoring other layer
        // surfaces' exclusive zones (e.g. lumen-panel) so the overlay truly
        // covers the screen.
        GtkLayerShell.set_exclusive_zone(this, -1);
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.EXCLUSIVE);

        decorated = false;
        add_css_class("kickoff-root");

        load_apps();
        search_db = new SearchDb(apps);

        build_ui();
        install_css();
        install_key_controller();

        // Autofocus the search entry once the window is mapped.
        map.connect(() => {
            search_entry.grab_focus();
        });
    }

    private void load_apps() {
        var list = new Gee.ArrayList<AppEntry>();
        foreach (var info in AppInfo.get_all()) {
            if (!info.should_show()) continue;
            var entry = new AppEntry(info);
            entry.launched.connect(() => close());
            list.add(entry);
        }
        list.sort((a, b) => GLib.strcmp(a.name, b.name));
        apps = new AppEntry[list.size];
        for (int i = 0; i < list.size; i++) apps[i] = list[i];
        stdout.printf("kickoff: %d apps\n", apps.length);
    }

    private void build_ui() {
        var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        root.set_halign(Gtk.Align.FILL);
        root.set_valign(Gtk.Align.FILL);
        root.set_hexpand(true);
        root.set_vexpand(true);

        // Search bar row, centered.
        var search_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        search_row.add_css_class("search-row");
        search_row.set_halign(Gtk.Align.CENTER);

        search_entry = new Gtk.SearchEntry();
        search_entry.add_css_class("kickoff-search");
        search_entry.set_placeholder_text("Search");
        // Lock to a fixed width so the entry doesn't grow with content and
        // shift the centered search row left/right as the user types.
        search_entry.set_size_request(320, -1);
        search_entry.set_hexpand(false);
        search_entry.set_halign(Gtk.Align.CENTER);
        search_entry.search_changed.connect(on_search_changed);
        search_entry.activate.connect(on_search_activate);
        search_row.append(search_entry);
        root.append(search_row);

        // Body: stack between paged grid and search results. Instant swap;
        // a crossfade would leave the grid faintly visible while results
        // appear, which reads as a layout glitch.
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

        // Dots row at the bottom.
        dots = new PageDots(grid.page_count);
        grid.page_changed.connect((p) => dots.set_active(p));
        root.append(dots);

        set_child(root);
    }

    // The CSS provider attaches to the global Gdk.Display, so it must only
    // be registered once per process — repeated KickoffWindow instances
    // would otherwise stack identical providers.
    private static bool css_installed = false;
    private static void install_css() {
        if (css_installed) return;
        css_installed = true;
        var css = new Gtk.CssProvider();
        css.load_from_string(KICKOFF_CSS);
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    private void install_key_controller() {
        var key = new Gtk.EventControllerKey();
        key.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        key.key_pressed.connect(on_key_pressed);
        ((Gtk.Widget) this).add_controller(key);
    }

    private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
        // Mask out lock keys so NumLock/CapsLock don't disable shortcuts.
        var mods = state & (Gdk.ModifierType.CONTROL_MASK
                          | Gdk.ModifierType.ALT_MASK
                          | Gdk.ModifierType.SHIFT_MASK
                          | Gdk.ModifierType.SUPER_MASK);

        switch (keyval) {
            case Gdk.Key.Escape:
                close();
                return true;
            case Gdk.Key.Left:
                if (!search_db.active && mods == 0) { grid.prev_page(); return true; }
                return false;
            case Gdk.Key.Right:
                if (!search_db.active && mods == 0) { grid.next_page(); return true; }
                return false;
            // Alt+N launches the Nth search result. Plain digits must fall
            // through to the search entry so users can type queries that
            // contain numbers (e.g. "qt6ct", "gimp2.10").
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
        // SearchEntry debounces search_changed (~100ms). Hitting Enter
        // immediately after typing would otherwise see stale state and
        // no-op. Re-evaluate the query before launching.
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
