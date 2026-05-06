using DrawKit;

/**
 * Interface every tray expansion page must implement.
 *
 * The Tray manages the animated expanding container and horizontal slide
 * transitions between pages.  Each ITrayPage is responsible only for
 * rendering and hit-testing its own content inside the rectangle it is given.
 */
public interface ITrayPage : GLib.Object {

    /** Short display title (currently unused but useful for debugging). */
    public abstract string get_title();

    /**
     * Called when this page becomes the active visible page.
     * Kick off any background work (network scans, data reads) here.
     */
    public abstract void on_activate();

    /**
     * Called when the user navigates away or the tray collapses.
     * Release keyboard hooks, cancel threads, etc.
     */
    public abstract void on_deactivate();

    /**
     * Render page content into the given rectangle.
     *
     * @param ctx  DrawKit context
     * @param x    Left edge of content area (already includes the slide offset)
     * @param y    Top edge of content area
     * @param w    Width of content area
     * @param h    Height of content area (grows as the tray expands)
     */
    public abstract void render(Context ctx, int x, int y, int w, int h);

    /** Mouse-button-press forwarded from Tray (panel-space coordinates). */
    public abstract void mouse_down(int mx, int my);

    /** Mouse-button-release forwarded from Tray. */
    public abstract void mouse_up(int mx, int my);

    /** Mouse-motion forwarded from Tray. */
    public abstract void mouse_motion(int mx, int my);

    /** Mouse scroll forwarded from Tray (positive = scroll down). */
    public abstract void mouse_scroll(int mx, int my, int amount);
}

// ─── Shared rendering helpers ─────────────────────────────────────────────────

/**
 * Draw text with LEFT-EDGE x and VISUAL-TOP y.
 *
 * DrawKit's draw_text() uses horizontal-centre x and baseline y.
 * This helper converts: ascender ≈ size × 0.82.
 */
public void pdt(Context ctx, string text, int left, int top, float size, Color col) {
    int tw = ctx.width_of(text, size);
    ctx.draw_text(text, left + tw / 2, top + (int)(size * 0.82f), size, col);
}

/** Draw text horizontally centred at cx, visual-top y. */
public void pdt_center(Context ctx, string text, int cx, int top, float size, Color col) {
    ctx.draw_text(text, cx, top + (int)(size * 0.82f), size, col);
}

/**
 * Convenience base class for tray pages.
 *
 * Provides no-op virtual defaults for all lifecycle and mouse handlers so that
 * subclasses only need to implement get_title() and render(), overriding the
 * other methods only when they actually need them.
 */
public abstract class BaseTrayPage : GLib.Object, ITrayPage {
    public abstract string get_title();
    public abstract void render(Context ctx, int x, int y, int w, int h);
    public virtual void on_activate()                            {}
    public virtual void on_deactivate()                          {}
    public virtual void mouse_down(int mx, int my)               {}
    public virtual void mouse_up(int mx, int my)                 {}
    public virtual void mouse_motion(int mx, int my)             {}
    public virtual void mouse_scroll(int mx, int my, int amount) {}
}
