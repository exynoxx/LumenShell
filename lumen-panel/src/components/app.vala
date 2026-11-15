public class AppEntry : Gtk.Button {

    public const int SLOT_WIDTH  = 70;
    public const int SLOT_HEIGHT = 60;
    public const int UNDERLINE_H = 4;
    public const int ICON_SIZE   = 40;

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
        if (PanelConfig.hover_style != PanelConfig.HoverStyle.FLAT) add_css_class("hover-custom");
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
                press_target = 0f;
                animate();
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
        tint_done = false;
        GLib.Icon? gicon = (info != null) ? info.get_icon() : null;
        var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
        if (gicon != null && (!(gicon is GLib.ThemedIcon) || theme.has_gicon(gicon))) {
            // Looked up at twice ICON_SIZE, drawn at ICON_SIZE: themes like Tela file a
            // 16 px drawing in a "16..32 Scalable" dir (and its @2x twin), which any 32 px
            // lookup picks and upscales into a blur. 64 px lands in the full-size art.
            icon_paintable = theme.lookup_by_gicon(
                gicon, ICON_SIZE * 2, scale_factor, Gtk.TextDirection.NONE, 0);
            image.set_from_paintable(icon_paintable);
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

    static bool hover_loaded = false;
    static Gdk.RGBA hover_val;
    static Gdk.RGBA hover_color () {
        return lazy_color(ref hover_loaded, ref hover_val, "app.hover", "rgba(255,255,255,0.20)");
    }

    const int   CHIP_INSET_X = 7;
    const int   CHIP_INSET_Y = 6;
    const int   CHIP_RADIUS  = 14;
    const float LIFT_PX      = 4f;
    const float LIFT_SCALE   = 0.06f;  // added to 1.0 at full lift
    const float LIFT_MS      = 120f;
    const float PRESS_SCALE  = 0.14f;  // subtracted from 1.0 at full press
    const float PRESS_MS     = 100f;

    const int   PILL_W  = 22;
    const int   PILL_H  = 4;
    const int   PILL_GAP = 4;          // px from the pill to the panel-side edge
    const float PILL_MS = 250f;
    const int   CARET_W = 14;
    const int   CARET_H = 7;

    const int TINT_INSET_X = 10;
    const int TINT_INSET_Y = 7;
    const int TINT_RADIUS  = 15;
    const int TINT_BAR_W   = 16;
    const int TINT_BAR_H   = 3;
    const int TINT_SAMPLE  = 16;       // px the icon is rendered at for averaging

    const int   COLUMN_INSET  = 8;
    const int   COLUMN_RADIUS = 12;
    const float COLUMN_ALPHA  = 0.65f;
    const int   SPLIT_INSET   = 8;
    const int   SPLIT_H       = 3;
    const int   SPLIT_GAP     = 3;
    static Gdk.RGBA SPLIT_DIM = Utils.rgba(1.0f, 1.0f, 1.0f, 0.35f);

    // Pinned-but-closed icons under dim-closed.
    const float DIM_OPACITY    = 0.65f;
    const float DIM_SATURATION = 0.2f;
    const float DIM_BRIGHTNESS = 0.75f;

    static Gdk.RGBA WHITE = Utils.rgba(1.0f, 1.0f, 1.0f, 1.0f);

    const int   OPEN_SHADE_H     = 12;   // px height of the bottom shading band
    const float OPEN_SHADE_ALPHA = 0.5f; // bottom-of-shade tint strength
    const int   OPEN_DOT_D       = 6;    // px diameter of the centered dot
    const int   OPEN_DOT_GAP     = 4;    // px from dot to the bottom edge
    const int   OPEN_TICK_D      = 5;
    const int   OPEN_TICK_ACTIVE_W = 9;  // first tick of the focused app
    const int   OPEN_TICK_GAP    = 3;
    const int   OPEN_TICK_MAX    = 3;
    const int   OPEN_PIP_D       = 4;
    const int   OPEN_EMBER_INSET = 18;
    const int   OPEN_EMBER_H     = 2;
    const int   OPEN_MARK_GAP    = 4;    // px from ticks/pip to the bottom edge
    static Gdk.RGBA OPEN_TICK_COLOR  = Utils.rgba(1.0f, 1.0f, 1.0f, 0.80f);
    static Gdk.RGBA OPEN_PIP_COLOR   = Utils.rgba(1.0f, 1.0f, 1.0f, 0.75f);
    static Gdk.RGBA OPEN_EMBER_COLOR = Utils.rgba(1.0f, 1.0f, 1.0f, 0.45f);
    const int   OPEN_SEG_INSET   = 14;
    const int   OPEN_SEG_H       = 2;
    static Gdk.RGBA OPEN_SEG_COLOR   = Utils.rgba(1.0f, 1.0f, 1.0f, 0.55f);

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

        bool active = is_active();
        // The pill grows in each time the entry becomes active.
        if (active != (pill_target > 0)) {
            pill_target = active ? 1f : 0f;
            pill_t = 0f;
            if (active && PanelConfig.active_indicator == PanelConfig.ActiveIndicator.PILL) animate();
        }

        var flags = get_state_flags();
        if (PanelConfig.hover_style == PanelConfig.HoverStyle.CHIP
                && (flags & Gtk.StateFlags.PRELIGHT) != 0 && !dragging) {
            Utils.fill_rounded(s, CHIP_INSET_X, CHIP_INSET_Y,
                               get_width() - 2 * CHIP_INSET_X, get_height() - 2 * CHIP_INSET_Y,
                               CHIP_RADIUS, hover_color());
        }

        if (active) {
            if (active_bg != null) active_bg(s);
        } else if (has_open_windows()) {
            if (open_bg != null) open_bg(s);
        }

        float lift  = ease_out(lift_t);
        float press = ease_out(press_t);
        bool  moved = lift > 0 || press > 0;
        if (moved) {
            float cx = get_width() / 2f, cy = get_height() / 2f;
            float k = (1f + LIFT_SCALE * lift) * (1f - PRESS_SCALE * press);
            s.save();
            var c = Graphene.Point();
            c.init(cx, cy - LIFT_PX * lift);
            s.translate(c);
            s.scale(k, k);
            c.init(-cx, -cy);
            s.translate(c);
        }
        if (lift > 0) {
            Gsk.Shadow[] shadow = { { Utils.rgba(0f, 0f, 0f, 0.35f * lift), 0f, 2f, 4f } };
            s.push_shadow(shadow);
        }
        bool dim = PanelConfig.open_indicator == PanelConfig.OpenIndicator.DIM_CLOSED
                   && !has_open_windows();
        if (dim) {
            s.push_opacity(DIM_OPACITY);
            push_desaturate(s);
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
        if (dim) {
            s.pop();      // color matrix
            s.pop();      // opacity
        }
        if (lift > 0) s.pop();   // shadow
        if (moved) s.restore();  // lift / press
        if (active) {
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

    // 0..1 linear progress, eased at draw time; one tick callback drives both.
    float lift_t = 0f;
    float lift_target = 0f;
    float pill_t = 0f;
    float pill_target = 0f;
    float press_t = 0f;
    float press_target = 0f;
    uint  anim_tick = 0;
    int64 last_frame = 0;

    public override void state_flags_changed (Gtk.StateFlags previous) {
        base.state_flags_changed(previous);
        bool hover = (get_state_flags() & Gtk.StateFlags.PRELIGHT) != 0;
        if (PanelConfig.hover_style == PanelConfig.HoverStyle.LIFT) {
            float target = hover ? 1f : 0f;
            if (target != lift_target) {
                lift_target = target;
                animate();
            }
        }
        float press = (get_state_flags() & Gtk.StateFlags.ACTIVE) != 0 && !dragging ? 1f : 0f;
        if (press != press_target) {
            press_target = press;
            animate();
        }
        if ((hover != ((previous & Gtk.StateFlags.PRELIGHT) != 0))) queue_draw();
    }

    void animate () {
        if (anim_tick == 0) anim_tick = add_tick_callback(on_tick);
    }

    bool on_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time();
        float dt = last_frame == 0 ? 0f : (float) ((now - last_frame) / 1000.0);
        last_frame = now;
        lift_t = approach(lift_t, lift_target, dt / LIFT_MS);
        pill_t = approach(pill_t, pill_target, dt / PILL_MS);
        press_t = approach(press_t, press_target, dt / PRESS_MS);
        queue_draw();
        if (lift_t == lift_target && pill_t == pill_target && press_t == press_target) {
            anim_tick = 0;
            last_frame = 0;
            return Source.REMOVE;
        }
        return Source.CONTINUE;
    }

    static float approach (float v, float target, float step) {
        return v < target ? float.min(v + step, target) : float.max(v - step, target);
    }

    static float ease_out (float t) {
        float u = 1f - t;
        return 1f - u * u * u;
    }

    void resolve_indicators () {
        switch (PanelConfig.active_indicator) {
            case PanelConfig.ActiveIndicator.PILL:
                active_fg = draw_active_pill; break;
            case PanelConfig.ActiveIndicator.TINT:
                active_bg = draw_active_tint_tile;
                active_fg = draw_active_tint_bar;
                break;
            case PanelConfig.ActiveIndicator.CARET:
                active_fg = draw_active_caret; break;
            case PanelConfig.ActiveIndicator.COLUMN:
                active_bg = draw_active_column; break;
            case PanelConfig.ActiveIndicator.SPLIT:
                active_fg = draw_active_split; break;
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
            case PanelConfig.OpenIndicator.PIP:     open_fg = draw_open_pip;               break;
            case PanelConfig.OpenIndicator.EMBER:   open_fg = draw_open_ember;             break;
            case PanelConfig.OpenIndicator.SEGMENTS: open_fg = draw_open_segments;         break;
            case PanelConfig.OpenIndicator.DIM_CLOSED:                                     break;
            case PanelConfig.OpenIndicator.TICKS:
                open_fg   = (s) => draw_open_ticks(s, false);
                // Ticks also mark focus, replacing the active fg indicator.
                active_fg = (s) => draw_open_ticks(s, true);
                break;
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

    void draw_active_pill (Gtk.Snapshot s) {
        float w = PILL_W * ease_out(pill_t);
        if (w <= 0) return;
        float y = PanelConfig.at_top ? PILL_GAP : get_height() - PILL_GAP - PILL_H;
        Utils.fill_rounded(s, (get_width() - w) / 2f, y, w, PILL_H, PILL_H / 2f, WHITE);
    }

    void draw_active_caret (Gtk.Snapshot s) {
        float cx = get_width() / 2f;
        float base_y = PanelConfig.at_top ? 0f : get_height();
        float tip_y  = PanelConfig.at_top ? CARET_H : get_height() - CARET_H;
        var pb = new Gsk.PathBuilder();
        pb.move_to(cx - CARET_W / 2f, base_y);
        pb.line_to(cx, tip_y);
        pb.line_to(cx + CARET_W / 2f, base_y);
        pb.close();
        s.append_fill(pb.to_path(), Gsk.FillRule.WINDING, WHITE);
    }

    // Rounded clip with only the corners away from the panel edge rounded:
    // the top ones normally, the bottom ones when the panel sits at the top.
    void push_edge_clip (Gtk.Snapshot s, Graphene.Rect area, float radius) {
        var r = Graphene.Size();
        r.init(radius, radius);
        var z = Graphene.Size();
        z.init(0, 0);
        var rr = Gsk.RoundedRect();
        if (PanelConfig.at_top) rr.init(area, z, z, r, r);
        else                    rr.init(area, r, r, z, z);
        s.push_rounded_clip(rr);
    }

    void draw_active_column (Gtk.Snapshot s) {
        float h = get_height();
        var area = Graphene.Rect();
        area.init(COLUMN_INSET, 0, get_width() - 2 * COLUMN_INSET, h);
        var clear = tint_color(); clear.alpha = 0f;
        var glow  = tint_color(); glow.alpha = COLUMN_ALPHA;
        var from = Graphene.Point();
        from.init(0, PanelConfig.at_top ? h : 0);
        var to = Graphene.Point();
        to.init(0, PanelConfig.at_top ? 0 : h);
        Gsk.ColorStop[] stops = { { 0.0f, clear }, { 1.0f, glow } };
        push_edge_clip(s, area, COLUMN_RADIUS);
        s.append_linear_gradient(area, from, to, stops);
        s.pop();
    }

    void draw_active_split (Gtk.Snapshot s) {
        int n = window_ids.size;
        if (n == 0) return;
        int focused = 0;
        for (int i = 0; i < n; i++) {
            var t = ToplevelStore.instance.find(window_ids[i]);
            if (t != null && t.activated) { focused = i; break; }
        }
        float seg = (get_width() - 2 * SPLIT_INSET - (n - 1) * SPLIT_GAP) / (float) n;
        float y = PanelConfig.at_top ? 0f : get_height() - SPLIT_H;
        for (int i = 0; i < n; i++) {
            var area = Graphene.Rect();
            area.init(SPLIT_INSET + i * (seg + SPLIT_GAP), y, seg, SPLIT_H);
            push_edge_clip(s, area, 2);
            s.append_color(i == focused ? WHITE : SPLIT_DIM, area);
            s.pop();
        }
    }

    // Saturation then brightness, as one matrix. Gsk applies it to a row
    // vector (out_j = sum_i in_i * m[i][j]), so row i carries input i's weight.
    void push_desaturate (Gtk.Snapshot s) {
        float sat = DIM_SATURATION, b = DIM_BRIGHTNESS;
        float[] lum = { 0.2126f, 0.7152f, 0.0722f };
        var m = new float[16];
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 3; j++)
                m[i * 4 + j] = b * ((i == j ? sat : 0f) + (1f - sat) * lum[i]);
        m[15] = 1f;
        var matrix = Graphene.Matrix();
        matrix.init_from_float(m);
        var offset = Graphene.Vec4();
        offset.init(0, 0, 0, 0);
        s.push_color_matrix(matrix, offset);
    }

    void draw_active_tint_tile (Gtk.Snapshot s) {
        var c = tint_color();
        var fill = c;
        fill.alpha = 0.45f;
        var rect = Graphene.Rect();
        rect.init(TINT_INSET_X, TINT_INSET_Y,
                  get_width() - 2 * TINT_INSET_X, get_height() - 2 * TINT_INSET_Y);
        var rr = Gsk.RoundedRect();
        rr.init_from_rect(rect, TINT_RADIUS);
        s.push_rounded_clip(rr);
        s.append_color(fill, rect);
        s.pop();
        float[] widths = { 1, 1, 1, 1 };
        Gdk.RGBA[] colors = { c, c, c, c };
        s.append_border(rr, widths, colors);
    }

    void draw_active_tint_bar (Gtk.Snapshot s) {
        var c = tint_color();
        c.red   = (c.red   + 1f) / 2f;
        c.green = (c.green + 1f) / 2f;
        c.blue  = (c.blue  + 1f) / 2f;
        Utils.fill_rounded(s, (get_width() - TINT_BAR_W) / 2f,
                           get_height() - 2 - TINT_BAR_H,
                           TINT_BAR_W, TINT_BAR_H, TINT_BAR_H / 2f, c);
    }

    // The icon's dominant colour, computed once on first draw (it needs the
    // native's renderer); falls back to the underline accent.
    bool tint_done = false;
    Gdk.RGBA tint_val;
    Gdk.RGBA tint_color () {
        if (!tint_done) {
            tint_done = true;
            if (!compute_tint(out tint_val)) tint_val = underline_color();
        }
        return tint_val;
    }

    // Alpha- and saturation-weighted mean over a tiny render of the icon, so
    // white/grey outlines and transparent margins don't wash the colour out.
    bool compute_tint (out Gdk.RGBA result) {
        result = {};
        var native = get_native();
        if (icon_paintable == null || native == null) return false;
        var renderer = native.get_renderer();
        if (renderer == null) return false;
        var snap = new Gtk.Snapshot();
        icon_paintable.snapshot(snap, TINT_SAMPLE, TINT_SAMPLE);
        var node = snap.free_to_node();
        if (node == null) return false;
        var vp = Graphene.Rect();
        vp.init(0, 0, TINT_SAMPLE, TINT_SAMPLE);
        var tex = renderer.render_texture(node, vp);

        int tw = tex.get_width(), th = tex.get_height();
        var px = new uint8[tw * th * 4];
        tex.download(px, tw * 4);   // premultiplied ARGB32, i.e. B,G,R,A bytes
        double r = 0, g = 0, b = 0, wsum = 0;
        for (int i = 0; i < tw * th * 4; i += 4) {
            double a = px[i + 3] / 255.0;
            if (a < 0.1) continue;
            double pb = px[i] / 255.0 / a, pg = px[i + 1] / 255.0 / a, pr = px[i + 2] / 255.0 / a;
            double mx = double.max(pr, double.max(pg, pb));
            double mn = double.min(pr, double.min(pg, pb));
            double sat = mx > 0 ? (mx - mn) / mx : 0;
            double wt = a * (0.1 + sat);
            r += pr * wt; g += pg * wt; b += pb * wt; wsum += wt;
        }
        if (wsum <= 0) return false;
        result = Utils.rgba((float) double.min(r / wsum, 1), (float) double.min(g / wsum, 1),
                            (float) double.min(b / wsum, 1), 1f);
        return true;
    }

    // Ray radii are keyed off the icon, not the slot, so the tips stay inside it.
    const int SUNSHINE_RAYS = 12;
    void draw_active_sunshine (Gtk.Snapshot s) {
        float cx = get_width() / 2f, cy = get_height() / 2f;
        float r_in  = ICON_SIZE / 2f + 3f;
        float r_out = float.min(ICON_SIZE / 2f + 12f, cy - 1f);   // clamp: panel is 60 px tall
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

    void draw_open_ticks (Gtk.Snapshot s, bool active) {
        int n = int.min(window_ids.size, OPEN_TICK_MAX);
        if (n == 0) return;
        float first = active ? OPEN_TICK_ACTIVE_W : OPEN_TICK_D;
        float x = (get_width() - (first + (n - 1) * (OPEN_TICK_D + OPEN_TICK_GAP))) / 2f;
        float y = get_height() - OPEN_MARK_GAP - OPEN_TICK_D;
        for (int i = 0; i < n; i++) {
            float w = i == 0 ? first : OPEN_TICK_D;
            Utils.fill_rounded(s, x, y, w, OPEN_TICK_D, OPEN_TICK_D / 2f,
                               (active && i == 0) ? WHITE : OPEN_TICK_COLOR);
            x += w + OPEN_TICK_GAP;
        }
    }

    void draw_open_segments (Gtk.Snapshot s) {
        int n = int.min(window_ids.size, OPEN_TICK_MAX);
        if (n == 0) return;
        float seg = (get_width() - 2 * OPEN_SEG_INSET - (n - 1) * OPEN_TICK_GAP) / (float) n;
        for (int i = 0; i < n; i++)
            Utils.fill_rounded(s, OPEN_SEG_INSET + i * (seg + OPEN_TICK_GAP),
                               get_height() - OPEN_SEG_H, seg, OPEN_SEG_H,
                               OPEN_SEG_H / 2f, OPEN_SEG_COLOR);
    }

    void draw_open_pip (Gtk.Snapshot s) {
        Utils.fill_rounded(s, (get_width() - OPEN_PIP_D) / 2f,
                           get_height() - OPEN_MARK_GAP - OPEN_PIP_D,
                           OPEN_PIP_D, OPEN_PIP_D, OPEN_PIP_D / 2f, OPEN_PIP_COLOR);
    }

    void draw_open_ember (Gtk.Snapshot s) {
        Utils.fill_rounded(s, OPEN_EMBER_INSET, get_height() - OPEN_EMBER_H,
                           get_width() - 2 * OPEN_EMBER_INSET, OPEN_EMBER_H,
                           OPEN_EMBER_H / 2f, OPEN_EMBER_COLOR);
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
