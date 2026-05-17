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
    private BlurBin blur_bin;

    // Blur fade animation. Target = MAX while a normal toplevel is focused,
    // 0 while the user is peeking the desktop (wallpaper click) — that's the
    // "fade away when you click through, fade in while you work" feel.
    private const double BLUR_MAX = 18.0;
    private const int64  BLUR_IN_US  = 800 * 1000;   // ease-in while working
    private const int64  BLUR_OUT_US = 300 * 1000;   // quick clear on peek
    private uint   blur_tick_id = 0;
    private int64  blur_anim_start_us = 0;
    private int64  blur_anim_duration_us = 0;
    private double blur_anim_from = 0.0;
    private double blur_anim_to   = 0.0;

    public DesktopWindow(Gtk.Application app) {
        Object(application: app);

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-desktop");
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
        // ON_DEMAND: keyboard focus follows pointer interaction. Clicking
        // the search entry hands the keyboard to us; clicking a normal
        // window hands it back. This is what makes the always-visible
        // drawer searchable without ever stealing focus from foreground
        // apps unprompted.
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);

        decorated = false;
        add_css_class("lumen-desktop-root");

        load_apps();
        search_db = new SearchDb(apps);

        build_ui();
        install_css();
        install_key_controller();

        map.connect(() => {
            search_entry.grab_focus();
            // Sync blur to whatever the focus state is at map time — if a
            // window is already focused, ramp up; otherwise stay clear.
            sync_blur_to_focus();
        });

        DesktopToplevels.instance.focus_changed.connect((any) => {
            sync_blur_to_focus();
        });
    }

    private void sync_blur_to_focus() {
        bool focused = DesktopToplevels.instance.any_focused;
        animate_blur_to(focused ? BLUR_MAX : 0.0, focused ? BLUR_IN_US : BLUR_OUT_US);
    }

    private void animate_blur_to(double target, int64 duration_us) {
        if (blur_bin == null) return;
        if (blur_bin.radius == target && blur_tick_id == 0) return;

        blur_anim_from = blur_bin.radius;
        blur_anim_to   = target;
        blur_anim_duration_us = duration_us;

        var clock = get_frame_clock();
        blur_anim_start_us = (clock != null) ? clock.get_frame_time() : GLib.get_monotonic_time();

        if (blur_tick_id == 0) {
            blur_tick_id = add_tick_callback(on_blur_tick);
        }
    }

    private bool on_blur_tick(Gtk.Widget w, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time();
        double t = (blur_anim_duration_us > 0)
            ? double.min(1.0, (now - blur_anim_start_us) / (double) blur_anim_duration_us)
            : 1.0;
        // ease-out-cubic — matches the gentle ramp used elsewhere in the
        // shell (panel reveal, banner fades).
        double e = 1.0 - GLib.Math.pow(1.0 - t, 3.0);
        blur_bin.radius = blur_anim_from + (blur_anim_to - blur_anim_from) * e;

        if (t >= 1.0) {
            blur_bin.radius = blur_anim_to;
            blur_tick_id = 0;
            return GLib.Source.REMOVE;
        }
        return GLib.Source.CONTINUE;
    }

    private void load_apps() {
        var list = new Gee.ArrayList<AppEntry>();
        foreach (var info in AppInfo.get_all()) {
            if (!info.should_show()) continue;
            var entry = new AppEntry(info);
            // Launching must NOT hide the desktop — it is always present.
            // Reset transient UI state (query + page) so the drawer doesn't
            // remain in a filtered/paginated state after the user dispatched
            // an app.
            entry.launched.connect(() => {
                // If a peek is currently active the just-launched window will
                // appear behind the slid-aside windows, which is confusing.
                // /stop is a no-op when the plugin is idle, so we can fire it
                // unconditionally instead of tracking peek state on this side.
                LumenDesktop.PeekIpc.stop();
                reset_view();
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

    private void peek_log(string msg) {
        try {
            var f = GLib.File.new_for_path("/tmp/lumen-desktop-peek.log");
            var os = f.append_to(GLib.FileCreateFlags.NONE);
            var ts = new GLib.DateTime.now_local();
            var line = "[%s] window: %s\n".printf(ts.format("%H:%M:%S.%f"), msg);
            os.write(line.data);
            os.close();
        } catch (GLib.Error e) {
            GLib.stderr.printf("peek_log failed: %s\n", e.message);
        }
    }

    private void trigger_peek(string reason) {
        peek_log(@"trigger_peek from $reason");
        LumenDesktop.PeekIpc.toggle();
    }

    private void build_ui() {
        var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        root.set_halign(Gtk.Align.FILL);
        root.set_valign(Gtk.Align.FILL);
        root.set_hexpand(true);
        root.set_vexpand(true);

        // Click on empty wallpaper area triggers a Wayfire desktop-peek.
        // BUBBLE phase (default) means tile / search-entry click controllers
        // get the press first. To make sure a tile launch never piggybacks
        // a peek, we ALSO walk up from the picked widget and skip the trigger
        // if any ancestor is a Gtk.Button or Gtk.Editable. That covers two
        // cases the propagation rules alone don't: child gestures that don't
        // explicitly claim the sequence, and non-button interactive widgets
        // like the SearchEntry.
        var click = new Gtk.GestureClick();
        click.set_button(0);
        click.pressed.connect((n_press, x, y) => {
            var picked = root.pick(x, y, Gtk.PickFlags.DEFAULT);
            var name   = picked == null ? "<null>" : picked.get_type().name();
            peek_log(@"root box clicked: x=$x y=$y n_press=$n_press picked=$name");

            for (var w = picked; w != null && w != root; w = w.get_parent()) {
                if (w is Gtk.Button || w is Gtk.Editable) {
                    peek_log(@"  skip peek: ancestor $(w.get_type().name()) is interactive");
                    return;
                }
            }

            trigger_peek("root-click");
            // Wallpaper click means "I want to interact with the drawer" —
            // hand keyboard focus to the search entry so the user can start
            // typing or arrow-navigate the grid immediately.
            search_entry.grab_focus();
            // Clear the blur immediately so the user sees crisp tiles while
            // peek slides the foreground windows out of the way. When focus
            // returns to a real window, focus_changed re-arms the fade-in.
            animate_blur_to(0.0, BLUR_OUT_US);
        });
        root.add_controller(click);

        // Layer-shell surfaces never get GDK_TOPLEVEL_STATE_FOCUSED, so
        // notify::is-active is silent. The pointer-enter on the root box is
        // the closest analogue to "focus shifted to lumen-desktop" we get;
        // log it for visibility but DO NOT trigger from it (would peek
        // every time the user mouses across the desktop between windows).
        var motion = new Gtk.EventControllerMotion();
        motion.enter.connect((x, y) => {
            peek_log(@"root box pointer-enter: x=$x y=$y");
        });
        motion.leave.connect(() => {
            peek_log("root box pointer-leave");
        });
        root.add_controller(motion);

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

        // Wrap the whole UI in a BlurBin so the GSK render pass applies a
        // GPU Gaussian blur over the search row + grid + dots in one shot.
        // The window's transparent background means the compositor wallpaper
        // shows through unblurred — only our painted pixels get blurred.
        blur_bin = new BlurBin();
        blur_bin.set_child(root);
        set_child(blur_bin);
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
