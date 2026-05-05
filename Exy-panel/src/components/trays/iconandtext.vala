using DrawKit;

/**
 * Base class for tray icons that combine a HoverableIcon with optional
 * metadata text.  All panel-expansion logic has been removed — the Tray
 * class manages expansion centrally via ITrayPage.
 */
public class IconAndText : Object, ITray, IHoverable {

    protected int    width;
    protected int    x;
    protected int    y;
    protected string text;

    // Last known mouse position (updated in mouse_motion, used by subclasses)
    protected int last_mx = -1;
    protected int last_my = -1;

    public HoverableIcon icon;

    public IconAndText(Context ctx, HoverableIcon icon, string label) {
        this.icon  = icon;
        this.text  = label;
        this.width = icon.get_width();
    }

    protected void set_text(string new_text) {
        text = new_text;
    }

    public int get_width() { return width; }

    public void set_position(int x, int y) {
        this.x = x;
        this.y = y;
        icon.set_position(x, y);
    }

    public virtual void mouse_motion(int mx, int my) {
        last_mx = mx;
        last_my = my;
        icon.mouse_motion(mx, my);
    }

    public virtual void render(Context ctx) {
        icon.render(ctx);
    }
}
