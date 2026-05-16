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
     * Push the page's hit-test rectangle. Called once by Tray after
     * construction with the fully-expanded content rectangle. The
     * rectangle never changes again, so mouse handlers can use it
     * without depending on the most recent render() args.
     */
    public abstract void set_bounds(int x, int y, int w, int h);

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
 * Owns the page's frozen layout rectangle (set once by Tray before the
 * first render) and renders via a template method so subclasses don't
 * have to keep re-doing the "use bounds_w if locked, else render-arg"
 * dance. Subclasses implement get_title() and render_content(); all
 * lifecycle and pointer handlers default to no-ops so they can be
 * overridden selectively.
 */
public abstract class BaseTrayPage : GLib.Object, ITrayPage {
    // Frozen layout rectangle — published once by Tray, locked thereafter.
    protected int bounds_x = 0;
    protected int bounds_y = 0;
    protected int bounds_w = 0;
    protected int bounds_h = 0;
    private   bool bounds_locked = false;

    // Default header / list separator colour shared by most pages.
    protected Color sep_color = Color(){r=0.22f, g=0.24f, b=0.35f, a=0.7f};

    public abstract string get_title();

    /**
     * Subclasses draw their content here. Bounds are guaranteed to be
     * locked by Tray before the first call, so just use bounds_w /
     * bounds_h directly. The (x, y) args carry the per-frame slide /
     * expand offset and must still be used for positioning.
     */
    protected abstract void render_content(Context ctx, int x, int y);

    /** Hook called once after the rectangle is first locked. */
    protected virtual void on_bounds_set() {}

    public virtual void set_bounds(int x, int y, int w, int h) {
        if (bounds_locked) return;
        bounds_x = x;  bounds_y = y;  bounds_w = w;  bounds_h = h;
        bounds_locked = true;
        on_bounds_set();
    }

    public void render(Context ctx, int x, int y, int w, int h) {
        render_content(ctx, x, y);
    }

    public virtual void on_activate()                            {}
    public virtual void on_deactivate()                          {}
    public virtual void mouse_down(int mx, int my)               {}
    public virtual void mouse_up(int mx, int my)                 {}
    public virtual void mouse_motion(int mx, int my)             {}
    public virtual void mouse_scroll(int mx, int my, int amount) {}
}
