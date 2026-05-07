using DrawKit;

/**
 * Base class for tray icons that wrap a HoverableIcon.
 * Expansion logic is managed centrally by Tray via ITrayPage.
 */
public class IconAndText : Object, ITray, IHoverable {

    protected int    width;
    protected int    x;
    protected int    y;

    public HoverableIcon icon;

    public IconAndText(HoverableIcon icon) {
        this.icon  = icon;
        this.width = icon.get_width();
    }

    public int get_width() { return width; }

    public void set_position(int x, int y) {
        this.x = x;
        this.y = y;
        icon.set_position(x, y);
    }

    public virtual void mouse_motion(int mx, int my) {
        icon.mouse_motion(mx, my);
    }

    public virtual void render(Context ctx) {
        icon.render(ctx);
    }
}
