using Gtk;
using Gee;

public class AppEntry : Gtk.Button {

    public const int SLOT_WIDTH  = 70;
    public const int SLOT_HEIGHT = 60;
    public const int UNDERLINE_H = 4;
    public const int ICON_SIZE   = 32;

    public string app_id { get; construct; }
    public string display_name { get; private set; }
    // Null when no .desktop file resolved: no launch, no themed icon.
    public DesktopAppInfo? info { get; private set; default = null; }
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
        this.info         = meta.info;

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
        resolve_indicators();

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
        if (info == null) {
            stderr.printf("AppEntry %s: no .desktop entry to launch\n", app_id);
            return;
        }
        try {
            info.launch(null, null);
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

    // The .desktop Icon key resolves to a GIcon (themed name, absolute path or
    // embedded data alike); lookup_by_gicon turns it into the paintable the
    // stacked-icon effect needs. has_gicon gates the bundled fallback — the
    // lookup itself never fails, it silently yields "image-missing".
    void load_icon () {
        GLib.Icon? gicon = (info != null) ? info.get_icon() : null;
        var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
        if (gicon != null && (!(gicon is GLib.ThemedIcon) || theme.has_gicon(gicon))) {
            image.set_from_gicon(gicon);
            icon_paintable = theme.lookup_by_gicon(
                gicon, ICON_SIZE, scale_factor, Gtk.TextDirection.NONE, 0);
            return;
        }
        image.set_from_resource("/dev/lumen/panel/icons/app.svg");
        icon_paintable = Gdk.Texture.from_resource("/dev/lumen/panel/icons/app.svg");
    }

    // Theme colors are resolved on first use, not in a static field
    // initializer: Theme.install() runs before the first AppEntry is built, but
    // nothing orders a field initializer against it.
    static Gdk.RGBA lazy_color (ref bool loaded, ref Gdk.RGBA slot,
                                string key, string fallback) {
        if (!loaded) {
            slot = Theme.color(key, fallback);
            loaded = true;
        }
        return slot;
    }

    // UNDERLINE / SUNSHINE accent, shared with @app_active_underline in the CSS
    // (which @-references can't reach from snapshot code).
    static bool underline_loaded = false;
    static Gdk.RGBA underline_val;
    static Gdk.RGBA underline_color () {
        return lazy_color(ref underline_loaded, ref underline_val,
                          "app.active-underline", "rgba(0,44,230,1)");
    }

    // RING active-indicator: a black ring around the icon instead of the
    // underline bar. Its circle matches the ROUND glass footprint (diameter =
    // the slot's short side).
    const int ACTIVE_RING_THICK = 2;   // px stroke width of the ring
    static Gdk.RGBA RING_COLOR = Utils.rgba(0.0f, 0.0f, 0.0f, 1.0f);

    // Open-but-not-focused apps get one of several indicator styles (chosen via
    // PanelConfig.open_indicator) so a running app is distinguishable from a
    // pinned-but-closed one. The dot, corner brackets and shade are all tinted
    // with the configurable `app.open-indicator-color`; the shade fades from
    // transparent to that color at OPEN_SHADE_ALPHA.
    const int   OPEN_SHADE_H     = 12;   // px height of the bottom shading band
    const float OPEN_SHADE_ALPHA = 0.5f; // bottom-of-shade tint strength
    const int   OPEN_DOT_D       = 6;    // px diameter of the centered dot
    const int   OPEN_DOT_GAP     = 4;    // px from dot to the bottom edge
    const int   OPEN_CORNER_LEN  = 8;    // px each corner bracket arm spans
    const int   OPEN_CORNER_THICK = 3;   // px thickness of the corner brackets

    static bool open_color_loaded = false;
    static Gdk.RGBA open_color_val;
    static Gdk.RGBA open_color () {
        return lazy_color(ref open_color_loaded, ref open_color_val,
                          "app.open-indicator-color", "rgba(61,122,255,1)");
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
    // The back copies all sit up-and-left of the front, so the group's bounding
    // box leans into the top-left corner. Shift the whole icon group back down-
    // and-right by half the stack's total span so it reads as centered.
    const float STACK_RECENTER = STACK_OFFSET;  // == (STACK_OFFSET * 2) / 2

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

        // Background indicators (glass sheens) paint behind everything so the
        // icon stays crisp on top; the edge-drawn styles run after base. Which
        // routine (if any) is used was resolved once at construction.
        if (is_active()) {
            if (active_bg != null) active_bg(s);
        } else if (has_open_windows()) {
            if (open_bg != null) open_bg(s);
        }

        // Recenter the whole icon group (front + back copies) for multi-window
        // apps so the up-and-left stack doesn't lean into the corner.
        bool stacked = window_ids.size > 1 && icon_paintable != null;
        if (stacked) {
            s.save();
            var r = Graphene.Point();
            r.init(STACK_RECENTER, STACK_RECENTER);
            s.translate(r);
        }

        // Back copies first so the real Gtk.Image (front) draws on top.
        if (stacked) {
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

        if (stacked) s.restore();  // stack recenter
        // Foreground indicators (over the icon) — style resolved at ctor.
        if (is_active()) {
            if (active_fg != null) active_fg(s);
        } else if (has_open_windows()) {
            if (open_fg != null) open_fg(s);
        }

        if (shifted) s.restore();
    }

    // The active/open indicator STYLE is fixed for the life of the process
    // (PanelConfig reads it once at startup), so bind each style to its draw
    // routine here rather than switching on the enum every snapshot(). `_bg`
    // routines paint behind the icon (pre-base); `_fg` routines paint over it.
    // A null field means "nothing to draw in that slot" (e.g. NONE, or GLASS
    // which only has a background).
    delegate void IndicatorDraw (Gtk.Snapshot s);
    IndicatorDraw? active_bg = null;
    IndicatorDraw? active_fg = null;
    IndicatorDraw? open_bg   = null;
    IndicatorDraw? open_fg   = null;

    void resolve_indicators () {
        switch (PanelConfig.active_indicator) {
            case PanelConfig.ActiveIndicator.RING:
                active_fg = draw_active_ring; break;
            case PanelConfig.ActiveIndicator.SUNSHINE:
                active_fg = draw_active_sunshine; break;
            case PanelConfig.ActiveIndicator.GLASS:
                active_bg = (s) => sheen(s, circle_rect(), -1, ACTIVE_GLASS_TOP, ACTIVE_GLASS_BOT);
                break;
            case PanelConfig.ActiveIndicator.CIRCLE:
                active_bg = (s) => sheen(s, circle_rect(), -1, ACTIVE_CIRCLE_FILL, ACTIVE_CIRCLE_FILL);
                break;
            case PanelConfig.ActiveIndicator.UNDERLINE:
            default:
                active_fg = draw_active_underline; break;
        }
        switch (PanelConfig.open_indicator) {
            case PanelConfig.OpenIndicator.DOT:     open_fg = draw_open_dot;               break;
            case PanelConfig.OpenIndicator.CORNERS: open_fg = draw_open_corners;           break;
            case PanelConfig.OpenIndicator.GLASS:   open_bg = (s) => draw_glass(s, false); break;
            case PanelConfig.OpenIndicator.ROUND:   open_bg = (s) => draw_glass(s, true);  break;
            case PanelConfig.OpenIndicator.NONE:                                           break;
            case PanelConfig.OpenIndicator.SHADE:
            default:                                open_fg = draw_open_shade;             break;
        }
    }

    // The centred circle every disc-shaped indicator (RING, active GLASS/CIRCLE,
    // open ROUND) shares: diameter = the slot's short side.
    Graphene.Rect circle_rect () {
        float w = get_width(), h = get_height();
        float d = float.min(w, h);
        var r = Graphene.Rect();
        r.init((w - d) / 2f, (h - d) / 2f, d, d);
        return r;
    }

    // Vertical two-stop gradient over `area`. `radius` < 0 means "half the
    // area's width" (a circle); 0 skips the clip entirely.
    void sheen (Gtk.Snapshot s, Graphene.Rect area, float radius,
                Gdk.RGBA top_color, Gdk.RGBA bot_color) {
        if (radius < 0) radius = area.get_width() / 2f;
        bool clipped = radius > 0;
        if (clipped) {
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(area, radius);
            s.push_rounded_clip(rr);
        }
        var top = Graphene.Point();
        top.init(0, area.get_y());
        var bot = Graphene.Point();
        bot.init(0, area.get_y() + area.get_height());
        Gsk.ColorStop[] stops = { { 0.0f, top_color }, { 1.0f, bot_color } };
        s.append_linear_gradient(area, top, bot, stops);
        if (clipped) s.pop();
    }

    // UNDERLINE active-indicator: the original accent bar under the icon.
    void draw_active_underline (Gtk.Snapshot s) {
        Utils.fill_rounded(s, 0, get_height() - UNDERLINE_H, get_width(),
                           UNDERLINE_H, 0, underline_color());
    }

    // RING active-indicator: a circle border around the icon.
    void draw_active_ring (Gtk.Snapshot s) {
        var area = circle_rect();
        var rr = Gsk.RoundedRect();
        rr.init_from_rect(area, area.get_width() / 2f);
        float[] widths = { ACTIVE_RING_THICK, ACTIVE_RING_THICK,
                           ACTIVE_RING_THICK, ACTIVE_RING_THICK };
        Gdk.RGBA[] colors = { RING_COLOR, RING_COLOR, RING_COLOR, RING_COLOR };
        s.append_border(rr, widths, colors);
    }

    // SUNSHINE active-indicator: triangular rays radiating around the icon (no
    // connecting ring). Inner/outer radii are keyed off the icon (not the slot)
    // so the tips stay inside the slot's short side.
    const int SUNSHINE_RAYS = 12;
    void draw_active_sunshine (Gtk.Snapshot s) {
        float cx = get_width() / 2f, cy = get_height() / 2f;
        float r_in  = ICON_SIZE / 2f + 3f;
        float r_out = ICON_SIZE / 2f + 12f;
        double step = 2.0 * Math.PI / SUNSHINE_RAYS;
        double half = step * 0.28;   // angular half-width of each ray's base
        var pb = new Gsk.PathBuilder();
        for (int i = 0; i < SUNSHINE_RAYS; i++) {
            double a = i * step;
            pb.move_to(cx + (float) (Math.cos(a - half) * r_in),
                       cy + (float) (Math.sin(a - half) * r_in));
            pb.line_to(cx + (float) (Math.cos(a) * r_out),
                       cy + (float) (Math.sin(a) * r_out));
            pb.line_to(cx + (float) (Math.cos(a + half) * r_in),
                       cy + (float) (Math.sin(a + half) * r_in));
            pb.close();
        }
        s.append_fill(pb.to_path(), Gsk.FillRule.WINDING, underline_color());
    }

    // GLASS active-indicator: a navy frosted disc behind the icon.
    static Gdk.RGBA ACTIVE_GLASS_TOP = Utils.rgba(0.08f, 0.16f, 0.35f, 0.60f);
    static Gdk.RGBA ACTIVE_GLASS_BOT = Utils.rgba(0.08f, 0.16f, 0.35f, 0.30f);
    // CIRCLE active-indicator: a flat white disc behind the icon so the focused
    // app lights up brighter than any open-but-unfocused one. Uniform, so it is
    // passed as both gradient stops.
    static Gdk.RGBA ACTIVE_CIRCLE_FILL = Utils.rgba(1.0f, 1.0f, 1.0f, 0.65f);

    // DOT open-indicator: a centered dot near the bottom edge.
    void draw_open_dot (Gtk.Snapshot s) {
        Utils.fill_rounded(s, (get_width() - OPEN_DOT_D) / 2f,
                           get_height() - OPEN_DOT_D - OPEN_DOT_GAP,
                           OPEN_DOT_D, OPEN_DOT_D, OPEN_DOT_D / 2f, open_color());
    }

    // CORNERS open-indicator: an L bracket in each corner — one arm along each
    // edge meeting there.
    void draw_open_corners (Gtk.Snapshot s) {
        float w = get_width(), h = get_height();
        float L = OPEN_CORNER_LEN, t = OPEN_CORNER_THICK;
        var c = open_color();
        Utils.fill_rounded(s, 0,     0,     L, t, 0, c);
        Utils.fill_rounded(s, 0,     0,     t, L, 0, c);
        Utils.fill_rounded(s, w - L, 0,     L, t, 0, c);
        Utils.fill_rounded(s, w - t, 0,     t, L, 0, c);
        Utils.fill_rounded(s, 0,     h - t, L, t, 0, c);
        Utils.fill_rounded(s, 0,     h - L, t, L, 0, c);
        Utils.fill_rounded(s, w - L, h - t, L, t, 0, c);
        Utils.fill_rounded(s, w - t, h - L, t, L, 0, c);
    }

    // SHADE open-indicator: a bottom band fading up from the indicator color.
    void draw_open_shade (Gtk.Snapshot s) {
        float h = get_height();
        var bounds = Graphene.Rect();
        bounds.init(0, h - OPEN_SHADE_H, get_width(), OPEN_SHADE_H);
        var top = open_color(); top.alpha = 0f;
        var bot = open_color(); bot.alpha = OPEN_SHADE_ALPHA;
        sheen(s, bounds, 0, top, bot);
    }

    // GLASS/ROUND open-indicator: a frosted fill behind the icon, a persistent
    // hover-like sheen. `round` clips it to the centred circle instead of the
    // inset rounded-rect footprint.
    void draw_glass (Gtk.Snapshot s, bool round) {
        if (round) {
            sheen(s, circle_rect(), -1, OPEN_GLASS_TOP, OPEN_GLASS_BOT);
            return;
        }
        float inset = OPEN_GLASS_INSET;
        var area = Graphene.Rect();
        area.init(inset, inset, get_width() - 2 * inset, get_height() - 2 * inset);
        sheen(s, area, OPEN_GLASS_RADIUS, OPEN_GLASS_TOP, OPEN_GLASS_BOT);
    }
}
