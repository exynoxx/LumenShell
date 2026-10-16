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

    // Rendered translate and AppBar's slide target; the dragged entry's offset
    // follows the pointer instead.
    public double drag_offset_x = 0;
    public double drag_target_x = 0;
    public bool   dragging      = false;

    Gtk.Image image;
    // Kept for drawing the stacked back copies of multi-window apps.
    Gdk.Paintable? icon_paintable = null;
    AppPopupMenu? popup = null;

    public signal void pin_toggled ();

    // AppBar owns sibling order; the gesture only reports begin / move / drop.
    public signal void drag_started ();
    public signal void drag_moved   (double offset_x);
    public signal void drag_dropped ();

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
            drag_dropped();
        });
        add_controller(drag);
    }

    const double DRAG_THRESHOLD = 8.0;

    public bool has_open_windows () { return window_ids.size > 0; }

    public void add_window (uint id) {
        if (!window_ids.contains(id)) window_ids.add(id);
        // A freshly-added window needs its minimize target right away, even if
        // no re-layout follows (compute_bounds no-ops until we're allocated).
        push_minimize_targets();
        queue_draw();
    }

    // Minimize target for the compositor's genie animation (without it the window
    // squeezes into its own origin). GTK root coords == layer-surface coords.
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
    }

    public void mark_focused (uint id) {
        var i = window_ids.index_of(id);
        if (i >= 0) cycle_idx = (i + 1) % window_ids.size;
        queue_draw();
    }

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

    // has_gicon gates the fallback: lookup_by_gicon never fails, it silently
    // yields "image-missing".
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

    // Resolved on first use, not in a static initializer: nothing orders a field
    // initializer after Theme.install().
    static Gdk.RGBA lazy_color (ref bool loaded, ref Gdk.RGBA slot,
                                string key, string fallback) {
        if (!loaded) {
            slot = Theme.color(key, fallback);
            loaded = true;
        }
        return slot;
    }

    // Same accent as @app_active_underline in the CSS (unreachable from snapshot code).
    static bool underline_loaded = false;
    static Gdk.RGBA underline_val;
    static Gdk.RGBA underline_color () {
        return lazy_color(ref underline_loaded, ref underline_val,
                          "app.active-underline", "rgba(0,44,230,1)");
    }

    const int ACTIVE_RING_THICK = 2;   // px stroke width of the ring
    static Gdk.RGBA RING_COLOR = Utils.rgba(0.0f, 0.0f, 0.0f, 1.0f);

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
    static Gdk.RGBA OPEN_GLASS_TOP = Utils.rgba(1.0f, 1.0f, 1.0f, 0.22f);
    static Gdk.RGBA OPEN_GLASS_BOT = Utils.rgba(1.0f, 1.0f, 1.0f, 0.08f);
    const int OPEN_GLASS_INSET  = 4;   // px gap from the slot edge
    const int OPEN_GLASS_RADIUS = 8;   // px corner rounding (matches .dragging)

    // Multi-window apps draw 2 back copies offset up-left; STACK_RECENTER shifts
    // the group back down-right so it reads as centred.
    const int STACK_OFFSET = 4;     // px diagonal step per back layer
    const float STACK_RECENTER = STACK_OFFSET;  // == (STACK_OFFSET * 2) / 2

    public override void snapshot (Gtk.Snapshot s) {
        bool shifted = drag_offset_x != 0 || dragging;
        if (shifted) {
            s.save();
            var t = Graphene.Point();
            t.init((float) drag_offset_x, dragging ? -6f : 0f);
            s.translate(t);
        }

        if (is_active()) {
            if (active_bg != null) active_bg(s);
        } else if (has_open_windows()) {
            if (open_bg != null) open_bg(s);
        }

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
        if (is_active()) {
            if (active_fg != null) active_fg(s);
        } else if (has_open_windows()) {
            if (open_fg != null) open_fg(s);
        }

        if (shifted) s.restore();
    }

    // Indicator styles are fixed at startup, so bind the draw routines once.
    // _bg paints behind the icon, _fg over it; null = nothing in that slot.
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

    void draw_active_underline (Gtk.Snapshot s) {
        Utils.fill_rounded(s, 0, get_height() - UNDERLINE_H, get_width(),
                           UNDERLINE_H, 0, underline_color());
    }

    void draw_active_ring (Gtk.Snapshot s) {
        var area = circle_rect();
        var rr = Gsk.RoundedRect();
        rr.init_from_rect(area, area.get_width() / 2f);
        float[] widths = { ACTIVE_RING_THICK, ACTIVE_RING_THICK,
                           ACTIVE_RING_THICK, ACTIVE_RING_THICK };
        Gdk.RGBA[] colors = { RING_COLOR, RING_COLOR, RING_COLOR, RING_COLOR };
        s.append_border(rr, widths, colors);
    }

    // Ray radii are keyed off the icon, not the slot, so the tips stay inside it.
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

    static Gdk.RGBA ACTIVE_GLASS_TOP = Utils.rgba(0.08f, 0.16f, 0.35f, 0.60f);
    static Gdk.RGBA ACTIVE_GLASS_BOT = Utils.rgba(0.08f, 0.16f, 0.35f, 0.30f);
    static Gdk.RGBA ACTIVE_CIRCLE_FILL = Utils.rgba(1.0f, 1.0f, 1.0f, 0.65f);

    void draw_open_dot (Gtk.Snapshot s) {
        Utils.fill_rounded(s, (get_width() - OPEN_DOT_D) / 2f,
                           get_height() - OPEN_DOT_D - OPEN_DOT_GAP,
                           OPEN_DOT_D, OPEN_DOT_D, OPEN_DOT_D / 2f, open_color());
    }

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

    void draw_open_shade (Gtk.Snapshot s) {
        float h = get_height();
        var bounds = Graphene.Rect();
        bounds.init(0, h - OPEN_SHADE_H, get_width(), OPEN_SHADE_H);
        var top = open_color(); top.alpha = 0f;
        var bot = open_color(); bot.alpha = OPEN_SHADE_ALPHA;
        sheen(s, bounds, 0, top, bot);
    }

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
