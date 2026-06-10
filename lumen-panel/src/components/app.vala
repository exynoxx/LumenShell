using Gtk;
using Gee;

// One taskbar entry. Drives icon, hover, active-window underline, popover.
public class AppEntry : Gtk.Button {

    public const int SLOT_WIDTH  = 70;
    public const int SLOT_HEIGHT = 60;
    public const int UNDERLINE_H = 5;
    public const int ICON_SIZE   = 32;

    public string app_id { get; construct; }
    public string display_name { get; private set; }
    public string launch_cmd   { get; private set; default = ""; }
    public string icon_name    { get; private set; default = ""; }
    public bool   is_pinned    { get; set;     default = false; }

    Gee.ArrayList<uint> window_ids = new Gee.ArrayList<uint>();
    int cycle_idx = 0;

    // Drag-to-reorder state. drag_offset_x is the current rendered horizontal
    // translate; drag_target_x is where AppBar wants this entry to slide to.
    // Both are driven by AppBar except for the lifted (dragging) entry, whose
    // offset follows the pointer directly.
    public double drag_offset_x = 0;
    public double drag_target_x = 0;
    public bool   dragging      = false;

    Gtk.Image image;
    // Resolved once in load_icon(); used to draw the dimmed back copies of the
    // stacked-icon effect for multi-window apps. The front layer stays the
    // Gtk.Image above.
    Gdk.Paintable? icon_paintable = null;
    AppPopupMenu? popup = null;

    public signal void pin_toggled ();
    public signal void unpin_and_removable ();

    // Drag-to-reorder: AppBar owns sibling order, so the gesture only reports
    // begin / move / drop and lets AppBar compute the reordering.
    public signal void drag_started ();
    public signal void drag_moved   (double offset_x);
    public signal void drag_dropped (double offset_x);

    public AppEntry (string app_id, AppMetadata meta) {
        GLib.Object(app_id: app_id);
        this.display_name = meta.name == "" ? app_id : meta.name;
        this.launch_cmd   = meta.launch_cmd;
        this.icon_name    = meta.icon;

        add_css_class("app-entry");
        set_size_request(SLOT_WIDTH, SLOT_HEIGHT);
        tooltip_text = display_name;

        image = new Gtk.Image() {
            pixel_size = ICON_SIZE,
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };
        set_child(image);
        load_icon();

        clicked.connect(on_primary_click);

        var rclick = new Gtk.GestureClick() { button = Gdk.BUTTON_SECONDARY };
        rclick.released.connect((n, x, y) => show_popup());
        add_controller(rclick);

        var drag = new Gtk.GestureDrag();
        drag.drag_update.connect((ox, oy) => {
            // Below the threshold, leave the gesture unclaimed so a near-still
            // press still resolves as a normal click (activate/cycle windows).
            if (!dragging && Math.fabs(ox) < DRAG_THRESHOLD) return;
            if (!dragging) {
                dragging = true;
                add_css_class("dragging");
                // Claiming cancels Gtk.Button's internal click gesture, so a
                // real drag won't also activate the app on release.
                drag.set_state(Gtk.EventSequenceState.CLAIMED);
                drag_started();
            }
            drag_offset_x = ox;
            drag_moved(ox);
            queue_draw();
        });
        drag.drag_end.connect((ox, oy) => {
            if (!dragging) return;
            dragging = false;
            remove_css_class("dragging");
            drag_dropped(ox);
        });
        add_controller(drag);
    }

    const double DRAG_THRESHOLD = 8.0;

    public bool has_open_windows () { return window_ids.size > 0; }

    public bool owns_window (uint id) { return window_ids.contains(id); }

    public void add_window (uint id) {
        if (!window_ids.contains(id)) window_ids.add(id);
        // A freshly-added window needs its minimize target right away, even if
        // no re-layout follows (compute_bounds no-ops until we're allocated).
        push_minimize_targets();
        queue_draw();
    }

    // Tell the compositor where this entry sits on the panel, so a minimize
    // animation (Wayfire's squeezimize "genie") flies each of our windows into
    // this button instead of collapsing the window into itself. Without a
    // target rectangle the compositor squeezes toward the window's own origin,
    // which is the "rolls up under itself" symptom. The rectangle is given in
    // the panel surface's coordinate space — GTK root coordinates match it 1:1
    // (layer-shell surface origin == window origin, same logical px).
    void push_minimize_targets () {
        if (window_ids.size == 0) return;
        var root = get_root() as Gtk.Window;
        if (root == null) return;
        var gdk_surface = root.get_surface();
        if (!(gdk_surface is Gdk.Wayland.Surface)) return;
        unowned Wl.Surface wl = ((Gdk.Wayland.Surface) gdk_surface).get_wl_surface();

        Graphene.Rect b;
        if (!compute_bounds((Gtk.Widget) root, out b)) return;
        int w = (int) b.get_width();
        int h = (int) b.get_height();
        if (w <= 0 || h <= 0) return;
        int x = (int) b.get_x();
        int y = (int) b.get_y();

        foreach (var id in window_ids)
            WLHooks.toplevel_set_rectangle_by_id(id, wl, x, y, w, h);
    }

    // Re-push targets whenever our slot moves or resizes (panel layout, tray
    // expansion, drag-reorder drops all re-allocate us).
    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate(width, height, baseline);
        push_minimize_targets();
    }

    public void remove_window (uint id) {
        var i = window_ids.index_of(id);
        if (i < 0) return;
        window_ids.remove_at(i);
        if (cycle_idx >= window_ids.size) cycle_idx = 0;
        queue_draw();

        if (!is_pinned && window_ids.size == 0) {
            unpin_and_removable();
        }
    }

    public void mark_focused (uint id) {
        var i = window_ids.index_of(id);
        if (i >= 0) cycle_idx = (i + 1) % window_ids.size;
        queue_draw();
    }

    // Active iff one of our windows is the focused toplevel in ToplevelStore.
    public bool is_active () {
        foreach (var id in window_ids) {
            var t = ToplevelStore.instance.find(id);
            if (t != null && t.activated) return true;
        }
        return false;
    }

    void on_primary_click () {
        if (has_open_windows()) {
            if (cycle_idx >= window_ids.size) cycle_idx = 0;
            var id = window_ids[cycle_idx];
            cycle_idx = (cycle_idx + 1) % window_ids.size;
            ToplevelStore.instance.activate(id);
            return;
        }
        launch_new_window();
    }

    public void launch_new_window () {
        if (launch_cmd == "") {
            stderr.printf("AppEntry %s: no launch command\n", app_id);
            return;
        }
        try {
            Process.spawn_command_line_async(launch_cmd);
        } catch (Error e) {
            stderr.printf("Launch failed for %s: %s\n", app_id, e.message);
        }
    }

    public void close_all_windows () {
        var ids = new Gee.ArrayList<uint>();
        ids.add_all(window_ids);
        foreach (var id in ids) ToplevelStore.instance.close(id);
    }

    void show_popup () {
        if (popup == null) popup = new AppPopupMenu(this);
        popup.refresh();
        popup.popup();
    }

    // Icon names go through the default display's Gtk.IconTheme; absolute
    // paths in the .desktop file are honored directly. Falls back to the
    // bundled generic-app glyph when nothing matches.
    void load_icon () {
        if (icon_name != "") {
            if (Path.is_absolute(icon_name) && FileUtils.test(icon_name, FileTest.EXISTS)) {
                image.set_from_file(icon_name);
                try {
                    icon_paintable = Gdk.Texture.from_filename(icon_name);
                } catch (Error e) {
                    icon_paintable = null;
                }
                return;
            }
            var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
            if (theme.has_icon(icon_name)) {
                image.set_from_icon_name(icon_name);
                icon_paintable = theme.lookup_icon(
                    icon_name, null, ICON_SIZE, scale_factor,
                    Gtk.TextDirection.NONE, 0);
                return;
            }
        }
        image.set_from_resource("/dev/lumen/panel/icons/app.svg");
        icon_paintable = Gdk.Texture.from_resource("/dev/lumen/panel/icons/app.svg");
    }

    // CSS @-references don't resolve outside style rules, so the underline
    // color is hard-coded here (matches @app_active_underline in style.css).
    static Gdk.RGBA UNDERLINE_COLOR = Utils.rgba(0.0f, 0.17f, 0.9f, 1.0f);

    // Open-but-not-focused apps get one of several indicator styles (chosen via
    // PanelConfig.open_indicator) so a running app is distinguishable from a
    // pinned-but-closed one. The dot, corner brackets and shade are all tinted
    // with the configurable `app.open-indicator-color` (resolved once below);
    // the shade fades from transparent to that color at OPEN_SHADE_ALPHA.
    const int   OPEN_SHADE_H     = 12;   // px height of the bottom shading band
    const float OPEN_SHADE_ALPHA = 0.5f; // bottom-of-shade tint strength
    const int   OPEN_DOT_D       = 6;    // px diameter of the centered dot
    const int   OPEN_DOT_GAP     = 4;    // px from dot to the bottom edge
    const int   OPEN_CORNER_LEN  = 8;    // px each corner bracket arm spans
    const int   OPEN_CORNER_THICK = 3;   // px thickness of the corner brackets

    // Resolved once from the theme; the panel re-reads on restart. Defaults to
    // the active-underline accent blue (#3d7aff) when the key is unset.
    static bool open_color_loaded = false;
    static Gdk.RGBA open_color_val;
    static Gdk.RGBA open_color () {
        if (!open_color_loaded) {
            open_color_val = Theme.color("app.open-indicator-color", "rgba(61,122,255,1)");
            open_color_loaded = true;
        }
        return open_color_val;
    }
    // Glass: a frosted translucent fill drawn behind the icon, mimicking the
    // CSS :hover background stuck on. Faint white sheen, brighter at the top.
    static Gdk.RGBA OPEN_GLASS_TOP = Utils.rgba(1.0f, 1.0f, 1.0f, 0.22f);
    static Gdk.RGBA OPEN_GLASS_BOT = Utils.rgba(1.0f, 1.0f, 1.0f, 0.08f);
    const int OPEN_GLASS_INSET  = 4;   // px gap from the slot edge
    const int OPEN_GLASS_RADIUS = 8;   // px corner rounding (matches .dragging)

    // Stacked-icon effect: an app with more than one window draws 2 copies of
    // its icon behind the real one, offset up-and-left, so a multi-window app
    // reads as a stack of papers at a glance.
    const int STACK_OFFSET = 4;     // px diagonal step per back layer

    public override void snapshot (Gtk.Snapshot s) {
        // Drag-to-reorder: shift everything we draw by the current offset (and
        // lift the dragged entry slightly) so the icon, stacked back-copies and
        // underline all move together.
        bool shifted = drag_offset_x != 0 || dragging;
        if (shifted) {
            s.save();
            var t = Graphene.Point();
            t.init((float) drag_offset_x, dragging ? -6f : 0f);
            s.translate(t);
        }

        // Glass fill goes behind everything (like the CSS :hover background) so
        // the icon stays crisp on top. The edge-drawn styles run after base.
        if (!is_active() && has_open_windows()
            && PanelConfig.open_indicator == PanelConfig.OpenIndicator.GLASS) {
            draw_glass(s);
        }

        // Back copies first so the real Gtk.Image (front) draws on top.
        if (window_ids.size > 1 && icon_paintable != null) {
            float cx = (get_width()  - ICON_SIZE) / 2f;
            float cy = (get_height() - ICON_SIZE) / 2f;
            for (int layer = 2; layer >= 1; layer--) {   // furthest first
                var p = Graphene.Point();
                p.init(cx - STACK_OFFSET * layer, cy - STACK_OFFSET * layer);
                s.save();
                s.translate(p);
                icon_paintable.snapshot(s, ICON_SIZE, ICON_SIZE);
                s.restore();  // transform
            }
        }

        base.snapshot(s);
        if (is_active()) {
            var rect = Graphene.Rect();
            rect.init(9, get_height() - UNDERLINE_H, get_width() - 18, UNDERLINE_H);
            s.append_color(UNDERLINE_COLOR, rect);
        } else if (has_open_windows()) {
            draw_open_indicator(s);
        }

        if (shifted) s.restore();
    }

    void draw_open_indicator (Gtk.Snapshot s) {
        float w = get_width();
        float h = get_height();
        switch (PanelConfig.open_indicator) {
            case PanelConfig.OpenIndicator.NONE:
            case PanelConfig.OpenIndicator.GLASS:   // drawn behind the icon, pre-base
                return;

            case PanelConfig.OpenIndicator.DOT:
                var dot = Graphene.Rect();
                dot.init((w - OPEN_DOT_D) / 2f, h - OPEN_DOT_D - OPEN_DOT_GAP,
                         OPEN_DOT_D, OPEN_DOT_D);
                var rr = Gsk.RoundedRect();
                rr.init_from_rect(dot, OPEN_DOT_D / 2f);
                s.push_rounded_clip(rr);
                s.append_color(open_color(), dot);
                s.pop();
                return;

            case PanelConfig.OpenIndicator.CORNERS:
                float L = OPEN_CORNER_LEN, t = OPEN_CORNER_THICK;
                // Each corner gets an L: one arm along each edge meeting there.
                fill(s, 0,     0,     L, t);  fill(s, 0,     0,     t, L);  // top-left
                fill(s, w - L, 0,     L, t);  fill(s, w - t, 0,     t, L);  // top-right
                fill(s, 0,     h - t, L, t);  fill(s, 0,     h - L, t, L);  // bottom-left
                fill(s, w - L, h - t, L, t);  fill(s, w - t, h - L, t, L);  // bottom-right
                return;

            case PanelConfig.OpenIndicator.SHADE:
            default:
                var bounds = Graphene.Rect();
                bounds.init(0, h - OPEN_SHADE_H, w, OPEN_SHADE_H);
                var top = Graphene.Point();
                top.init(0, h - OPEN_SHADE_H);
                var bot = Graphene.Point();
                bot.init(0, h);
                var c = open_color();
                var shade_top = c; shade_top.alpha = 0f;
                var shade_bot = c; shade_bot.alpha = OPEN_SHADE_ALPHA;
                Gsk.ColorStop[] stops = {
                    { 0.0f, shade_top },
                    { 1.0f, shade_bot },
                };
                s.append_linear_gradient(bounds, top, bot, stops);
                return;
        }
    }

    // Append a solid indicator-colored rectangle (corner-bracket arm).
    void fill (Gtk.Snapshot s, float x, float y, float w, float h) {
        var r = Graphene.Rect();
        r.init(x, y, w, h);
        s.append_color(open_color(), r);
    }

    // Frosted rounded fill behind the icon — a persistent hover-like sheen.
    void draw_glass (Gtk.Snapshot s) {
        float w = get_width(), h = get_height();
        float inset = OPEN_GLASS_INSET;
        var area = Graphene.Rect();
        area.init(inset, inset, w - 2 * inset, h - 2 * inset);
        var rr = Gsk.RoundedRect();
        rr.init_from_rect(area, OPEN_GLASS_RADIUS);
        s.push_rounded_clip(rr);
        var top = Graphene.Point();
        top.init(0, inset);
        var bot = Graphene.Point();
        bot.init(0, h - inset);
        Gsk.ColorStop[] stops = {
            { 0.0f, OPEN_GLASS_TOP },
            { 1.0f, OPEN_GLASS_BOT },
        };
        s.append_linear_gradient(area, top, bot, stops);
        s.pop();
    }
}
