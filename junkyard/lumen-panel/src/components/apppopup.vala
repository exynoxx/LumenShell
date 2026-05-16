using DrawKit;

/**
 * AppPopup — the right-click context menu for taskbar app entries.
 *
 * Manages its own position, animation and hit-testing.  Panel connects
 * to the signals to perform the actual app manipulation.
 */
public class AppPopup : GLib.Object {

    public signal void pin_toggled(App app);
    public signal void new_window_requested(App app);
    public signal void close_windows_requested(App app);

    public App? app { get; private set; }

    // popup_h is mutated in-place by Transition1D
    private int popup_h = 0;
    private int popup_x = 0;
    private int popup_y = 0;
    private int popup_action_hovered = -1;
    private int popup_action_pressed = -1;

    private int screen_width;

    private Color bg_color;
    private Color border_color;
    private Color sep_color;
    private Color text_color;
    private Color action_color;
    private Color action_bg_color;

    public AppPopup(int screen_width) {
        this.screen_width = screen_width;
        bg_color       = Color(){r=0.08f, g=0.09f, b=0.14f, a=0.98f};
        border_color   = Color(){r=0.20f, g=0.24f, b=0.38f, a=1f};
        sep_color      = Color(){r=0.20f, g=0.24f, b=0.38f, a=0.8f};
        text_color     = Color(){r=0.92f, g=0.93f, b=0.98f, a=1f};
        action_color   = Color(){r=0.74f, g=0.80f, b=1f,    a=1f};
        action_bg_color = Color(){r=0.16f, g=0.20f, b=0.30f, a=0f};
    }

    public int get_height() { return popup_h; }

    public void show_for(App target) {
        app = target;

        var target_x = target.x + (APP_WIDTH - POPUP_W) / 2;
        if (target_x < 4) target_x = 4;
        if (target_x + POPUP_W > screen_width - 4)
            target_x = screen_width - POPUP_W - 4;

        popup_x = target_x;
        popup_h = 0;
        popup_action_hovered = -1;
        popup_action_pressed = -1;
        animations.add(new Transition1D(POPUP_ANIM_ID, &popup_h, target_height(), 0.18d));
        update_y();
    }

    public void hide() {
        if (app == null) return;
        app = null;
        popup_h = 0;
        popup_action_hovered = -1;
        popup_action_pressed = -1;
    }

    public bool is_open() { return app != null; }

    public bool contains(int mx, int my) {
        if (!is_open()) return false;
        update_y();
        return mx >= popup_x && mx <= popup_x + POPUP_W
            && my >= popup_y && my <= popup_y + popup_h;
    }

    public int action_at(int mx, int my) {
        if (!contains(mx, my)) return -1;
        if (my < popup_y + POPUP_TITLE_H) return -1;
        int idx = (my - (popup_y + POPUP_TITLE_H)) / POPUP_ROW_H;
        if (idx < 0 || idx >= action_count()) return -1;
        return idx;
    }

    public void on_mouse_motion(int mx, int my) {
        var old = popup_action_hovered;
        popup_action_hovered = action_at(mx, my);
        if (old != popup_action_hovered) redraw = true;
    }

    /** Returns true if the popup handled the event (caller should not propagate). */
    public bool on_mouse_down(int mx, int my) {
        var idx = action_at(mx, my);
        if (idx >= 0) {
            popup_action_pressed = idx;
            redraw = true;
            return true;
        }
        if (contains(mx, my)) {
            redraw = true;
            return true;
        }
        return false;
    }

    /** Returns true if an action was executed (caller should hide the popup). */
    public bool on_mouse_up(int mx, int my) {
        var was_pressed = popup_action_pressed;
        popup_action_pressed = -1;
        var idx = action_at(mx, my);
        if (was_pressed >= 0 && was_pressed == idx) {
            execute_action(idx);
            return true;
        }
        return false;
    }

    public void render(Context ctx) {
        if (!is_open() || app == null || popup_h <= 0) return;
        update_y();

        ctx.draw_rect_rounded(popup_x, popup_y, POPUP_W, popup_h, 10f, bg_color);
        ctx.draw_rect_rounded(popup_x, popup_y, POPUP_W, 1, 10f, border_color);

        if (popup_h > POPUP_TITLE_H)
            ctx.draw_rect(popup_x + 10, popup_y + POPUP_TITLE_H, POPUP_W - 20, 1, sep_color);

        ctx.draw_text(app.title, popup_x + POPUP_W / 2, popup_y + 26, 16f, text_color);

        var n = action_count();
        for (int i = 0; i < n; i++) {
            var row_y  = popup_y + POPUP_TITLE_H + i * POPUP_ROW_H;
            action_bg_color.a = 0f;
            if (popup_action_pressed == i) {
                action_bg_color.a = 0.45f;
            } else if (popup_action_hovered == i) {
                action_bg_color.a = 0.30f;
            }

            if (action_bg_color.a > 0f)
                ctx.draw_rect(popup_x + 4, row_y + 2, POPUP_W - 8, POPUP_ROW_H - 4, action_bg_color);

            if (i > 0)
                ctx.draw_rect(popup_x + 14, row_y, POPUP_W - 28, 1, sep_color);

            ctx.draw_text(action_label(i), popup_x + POPUP_W / 2, row_y + 22, 15f, action_color);
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────

    private void update_y() {
        popup_y = APP_Y - popup_h - POPUP_GAP;
    }

    private int target_height() {
        return POPUP_TITLE_H + action_count() * POPUP_ROW_H;
    }

    private int action_count() {
        if (app == null) return 0;
        return app.has_open_windows() ? 3 : 2;
    }

    private string action_label(int idx) {
        if (app == null) return "";
        if (idx == 0) return app.is_pinned ? "Unpin" : "Pin";
        if (idx == 1) return "New window";
        if (idx == 2 && app.has_open_windows()) return "Close windows";
        return "";
    }

    private void execute_action(int idx) {
        if (app == null) return;
        if (idx == 0) pin_toggled(app);
        else if (idx == 1) new_window_requested(app);
        else if (idx == 2 && app.has_open_windows()) close_windows_requested(app);
    }
}
