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

    // ── Tray icon list ────────────────────────────────────────────────────
    private ITray[] trays = {};

    // Parallel arrays: pages[i] is owned by trays[page_owner[i]]
    private ITrayPage[] pages      = {};
    private int[]       page_owner = {};

    // ── Expansion state ───────────────────────────────────────────────────
    private int expanded_height = 0;   // mutated in-place by Transition1D
    private int active_page_idx = -1;  // -1 = no active page / collapsed

    // page_slide_x: offset of the virtual page band.
    // Page i renders at (tray_x + i * tray_width + page_slide_x).
    private int page_slide_x = 0;

    // ── Cached geometry ───────────────────────────────────────────────────
    private int x;
    private int width;

    // ── Last mouse position ───────────────────────────────────────────────
    private int last_mx = -1;
    private int last_my = -1;

    // ─────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────

    public Tray(Context ctx, int screen_width) {
        this.ctx          = ctx;
        this.screen_width = screen_width;

        var wifi    = new WifiTray(ctx);
        var battery = new BatteryTray(ctx);
        var clock   = new Clock(ctx);
        var exit    = new ExitTray(ctx);

        trays += wifi;
        trays += battery;
        trays += clock;
        trays += exit;

        // Build pages array in tray-icon order
        for (int i = 0; i < trays.length; i++) {
            if (trays[i] is IHasPage) {
                pages      += ((IHasPage) trays[i]).get_page();
                page_owner += i;
            }
        }

        layout_children();
    }

    // ─────────────────────────────────────────────────────────────────────
    // Layout  (called every frame so animation is smooth)
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Icon row sits at the TOP of the expanded container.
     * As expanded_height grows the icons glide upward; page content
     * is revealed below them.
     */
    private void layout_children() {
        int icon_row_y = TRAY_Y - expanded_height;

        var current_x = screen_width - MARGIN_RIGHT;
        for (int i = trays.length - 1; i >= 0; i--) {
            current_x -= trays[i].get_width() + SPACING;
            trays[i].set_position(current_x, icon_row_y);
        }

        this.x     = current_x - SPACING;
        this.width = screen_width - MARGIN_RIGHT - this.x;
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
                animations.add(new Transition1D(EXPAND_ANIM_ID,
                    &expanded_height, EXPAND_FULL, 0.28d));

            // Slide the virtual page band so the target page is centred
            int target_slide = -page_idx * this.width;
            animations.add(new Transition1D(SLIDE_ANIM_ID,
                &page_slide_x, target_slide, 0.22d));

            active_page_idx = page_idx;
            pages[page_idx].on_activate();
        }
        redraw = true;
    }

    private void collapse() {
        if (active_page_idx >= 0) {
            pages[active_page_idx].on_deactivate();
            active_page_idx = -1;
        }
        animations.add(new Transition1D(EXPAND_ANIM_ID,
            &expanded_height, 0, 0.24d));
        redraw = true;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Input forwarding
    // ─────────────────────────────────────────────────────────────────────

    public void on_mouse_down() {
        // 1. Page-icon clicks
        for (int p = 0; p < pages.length; p++) {
            var hp = (IHasPage) trays[page_owner[p]];
            if (hp.is_icon_hovered()) {
                toggle_page(p);
                return;
            }
        }

        // 2. Non-expandable icons
        foreach (var t in trays) {
            if (!(t is IHasPage) && t is IClickable)
                ((IClickable) t).mouse_down();
        }

        // 3. Page content area
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

        // Collapse when the pointer leaves the expanded container
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

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    public void render() {
        layout_children();

        int icon_row_y = TRAY_Y - expanded_height;
        int bg_h = TRAY_HEIGHT + expanded_height;

        // ── Container background ──────────────────────────────────────────
        ctx.draw_rect_rounded(this.x, icon_row_y, this.width, bg_h, 22f,
            Color(){r=0.07f, g=0.08f, b=0.12f, a=0.97f});

        // ── Page content ──────────────────────────────────────────────────
        int ct = content_top();
        int ch = content_height();

        if (ch > 4 && active_page_idx >= 0) {
            // Separator line
            ctx.draw_rect(this.x + 12, ct - 1, this.width - 24, 1,
                Color(){r=0.20f, g=0.22f, b=0.34f, a=0.6f});

            // Stencil-clip so pages cannot overdraw the icon row
            ctx.stencil_push();
            ctx.draw_rect(this.x, ct, this.width, ch,
                Color(){r=1f, g=1f, b=1f, a=1f});
            ctx.stencil_apply();

            // Render pages in the virtual horizontal band.
            // During a slide transition two pages will be partially visible.
            for (int p = 0; p < pages.length; p++) {
                int px = this.x + p * this.width + page_slide_x;
                if (px + this.width < this.x || px > this.x + this.width) continue;
                pages[p].render(ctx, px, ct, this.width, ch);
            }

            ctx.stencil_pop();
        }

        // ── Icons (on top of page content) ────────────────────────────────
        foreach (var t in trays)
            t.render(ctx);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Geometry helpers
    // ─────────────────────────────────────────────────────────────────────

    /** Top y of the page content area (just below the icon row). */
    private int content_top() {
        return TRAY_Y - expanded_height + TRAY_HEIGHT;
    }

    /** Height of the page content area. */
    private int content_height() {
        return expanded_height - TRAY_HEIGHT;
    }
}
