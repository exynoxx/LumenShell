using DrawKit;
using GLES2;

public const int FONT_SIZE = 16;

public class Tray {

    // ── Geometry constants ────────────────────────────────────────────────
    public const int MARGIN_RIGHT = 20;
    public const int TRAY_HEIGHT  = EXCLUSIVE_HEIGHT - 12;   // 48
    public const int MARGIN_TOP   = (EXCLUSIVE_HEIGHT - TRAY_HEIGHT) / 2;
    public const int TRAY_Y       = HEIGHT - TRAY_HEIGHT - MARGIN_TOP; // 246
    public const int SPACING      = 20;

    // Full expansion: icon row slides all the way to y = 0
    private const int EXPAND_FULL = TRAY_Y;   // 246

    // ── Animation IDs ─────────────────────────────────────────────────────
    private const int EXPAND_ANIM_ID = 1;
    private const int SLIDE_ANIM_ID  = 2;

    // ── Dependencies ──────────────────────────────────────────────────────
    private unowned Context ctx;
    private int screen_width;

    // ── Tray icon list — frozen after construction ────────────────────────
    // trays / pages / page_owner / child_x are populated once in the ctor
    // and never mutated again. Their lengths and contents are invariants
    // for the rest of the program's lifetime.
    private ITray[]     trays      = {};
    private ITrayPage[] pages      = {};
    private int[]       page_owner = {};
    private int[]       child_x    = {};   // per-icon fixed x position

    // ── Expansion state ───────────────────────────────────────────────────
    private int expanded_height = 0;   // mutated in-place by Transition1D
    private int active_page_idx = -1;  // -1 = no active page / collapsed

    public int get_expanded_height() { return expanded_height; }

    // page_slide_x: offset of the virtual page band.
    private int page_slide_x = 0;

    // ── Fixed geometry — computed once in the ctor, then read-only ────────
    private int x;
    private int width;

    // ── Last mouse position ───────────────────────────────────────────────
    private int last_mx = -1;
    private int last_my = -1;

    // ── Cached colors ─────────────────────────────────────────────────────
    private Color bg_color  = Theme.tray_bg;
    private Color sep_color = Color(){r=0.20f, g=0.22f, b=0.34f, a=0.6f};
    private Color stencil_color = Color(){r=1f, g=1f, b=1f, a=1f};

    // ─────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────

    public Tray(Context ctx, int screen_width) {
        this.ctx          = ctx;
        this.screen_width = screen_width;

        var wifi    = new WifiTray();
        var battery = new BatteryTray();
        var sound   = new SoundTray(ctx);
        var clock   = new Clock(ctx);
        var exit    = new ExitTray();

        trays += wifi;
        trays += battery;
        trays += sound;
        trays += clock;
        trays += exit;

        // Build pages array in tray-icon order
        for (int i = 0; i < trays.length; i++) {
            if (trays[i] is IHasPage) {
                pages      += ((IHasPage) trays[i]).get_page();
                page_owner += i;
            }
        }

        compute_layout();
        publish_page_bounds();
        position_icons(TRAY_Y);
        sync_page_icon_states();
    }

    // ─────────────────────────────────────────────────────────────────────
    // Layout
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Compute the tray's horizontal layout once. Each ITray contract
     * requires get_width() to return a value stable for the program's
     * lifetime, so x / width / child_x[] never need to be recomputed.
     */
    private void compute_layout() {
        child_x = new int[trays.length];
        var current_x = screen_width - MARGIN_RIGHT;
        for (int i = trays.length - 1; i >= 0; i--) {
            current_x -= trays[i].get_width() + SPACING;
            child_x[i] = current_x;
        }
        this.x     = current_x - SPACING;
        this.width = screen_width - MARGIN_RIGHT - this.x;
    }

    /**
     * Push each page its fully-expanded hit-test rectangle. Pages can
     * then resolve mouse events without depending on render-time state.
     */
    private void publish_page_bounds() {
        int ct = TRAY_HEIGHT;                  // content_top when fully expanded
        int ch = EXPAND_FULL - TRAY_HEIGHT;    // content_height when fully expanded
        foreach (var p in pages)
            p.set_bounds(this.x, ct, this.width, ch);
    }

    /**
     * Update only the icon row's y so the bar can slide vertically as
     * the tray expands. x positions were fixed at construction.
     */
    private void position_icons(int icon_row_y) {
        for (int i = 0; i < trays.length; i++)
            trays[i].set_position(child_x[i], icon_row_y);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Page expansion / switching
    // ─────────────────────────────────────────────────────────────────────

    private void toggle_page(int page_idx) {
        if (page_idx == active_page_idx) {
            collapse();
        } else {
            if (active_page_idx >= 0)
                pages[active_page_idx].on_deactivate();

            if (expanded_height == 0)
                animations.add(new Transition1D(EXPAND_ANIM_ID, &expanded_height, EXPAND_FULL, 0.28d));

            int target_slide = -page_idx * this.width;
            animations.add(new Transition1D(SLIDE_ANIM_ID, &page_slide_x, target_slide, 0.22d));

            active_page_idx = page_idx;
            sync_page_icon_states();
            pages[page_idx].on_activate();
        }
        redraw = true;
    }

    private void collapse() {
        if (active_page_idx >= 0) {
            pages[active_page_idx].on_deactivate();
            active_page_idx = -1;
            sync_page_icon_states();
        }
        animations.add(new Transition1D(EXPAND_ANIM_ID, &expanded_height, 0, 0.24d));
        redraw = true;
    }

    private void sync_page_icon_states() {
        for (int p = 0; p < pages.length; p++) {
            var owner = (IHasPage) trays[page_owner[p]];
            owner.set_page_active(p == active_page_idx);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Input forwarding
    // ─────────────────────────────────────────────────────────────────────

    public void on_mouse_down() {
        for (int p = 0; p < pages.length; p++) {
            var hp = (IHasPage) trays[page_owner[p]];
            if (hp.is_icon_hovered()) {
                toggle_page(p);
                return;
            }
        }

        foreach (var t in trays) {
            if (!(t is IHasPage) && t is IClickable)
                ((IClickable) t).mouse_down();
        }

        if (active_page_idx >= 0) {
            int ct = content_top();
            if (last_my >= ct && last_my <= TRAY_Y)
                pages[active_page_idx].mouse_down(last_mx, last_my);
        }
    }

    public void on_mouse_up() {
        foreach (var t in trays) {
            if (!(t is IHasPage) && t is IClickable)
                ((IClickable) t).mouse_up();
        }
        if (active_page_idx >= 0)
            pages[active_page_idx].mouse_up(last_mx, last_my);
    }

    public void on_mouse_motion(int mx, int my) {
        last_mx = mx;
        last_my = my;

        foreach (var tray in trays)
            if (tray is IHoverable)
                ((IHoverable) tray).mouse_motion(mx, my);

        if (active_page_idx >= 0)
            pages[active_page_idx].mouse_motion(mx, my);

        if (active_page_idx >= 0 && expanded_height > 0) {
            int icon_row_y = TRAY_Y - expanded_height;
            bool in_tray   = mx >= this.x
                          && mx <= this.x + this.width
                          && my >= icon_row_y
                          && my <= TRAY_Y + TRAY_HEIGHT;
            if (!in_tray) collapse();
        }

        redraw = true;
    }

    public void on_mouse_leave() {
        on_mouse_motion(-1, -1);
    }

    public void on_mouse_scroll(int amount) {
        if (active_page_idx < 0 || amount == 0) return;

        int ct = content_top();
        if (last_my >= ct && last_my <= TRAY_Y)
            pages[active_page_idx].mouse_scroll(last_mx, last_my, amount);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    public void render() {
        int icon_row_y = TRAY_Y - expanded_height;
        position_icons(icon_row_y);

        int bg_h = TRAY_HEIGHT + expanded_height;

        ctx.draw_rect_rounded(this.x, icon_row_y, this.width, bg_h, 22f, bg_color);

        int ct = content_top();
        int ch = content_height();

        if (ch > 4 && active_page_idx >= 0) {
            ctx.draw_rect(this.x + 12, ct - 1, this.width - 24, 1, sep_color);

            ctx.stencil_push();
            ctx.draw_rect(this.x, ct, this.width, ch, stencil_color);
            ctx.stencil_apply();

            for (int p = 0; p < pages.length; p++) {
                int page_x = this.x + p * this.width + page_slide_x;
                if (page_x + this.width <= this.x || page_x >= this.x + this.width) continue;
                pages[p].render(ctx, page_x, ct, this.width, ch);
            }

            ctx.stencil_pop();
        }

        foreach (var t in trays)
            t.render(ctx);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Geometry helpers
    // ─────────────────────────────────────────────────────────────────────

    private int content_top() {
        return TRAY_Y - expanded_height + TRAY_HEIGHT;
    }

    private int content_height() {
        return expanded_height - TRAY_HEIGHT;
    }
}
