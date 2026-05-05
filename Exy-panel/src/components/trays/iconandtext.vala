using DrawKit;

public class IconAndText : Object, ITray, IHoverable {

    private static int _next_anim_id = 20;
    private int anim_id;

    protected int width;
    protected int x;
    protected int y;

    protected string text;
    protected bool opened = false;
    protected int panel_height = 0;
    protected int panel_max_height;

    // Last known mouse position — updated in mouse_motion, used by subclass panel hit-testing
    protected int last_mx = -1;
    protected int last_my = -1;

    public HoverableIcon icon;

    public IconAndText(Context ctx, HoverableIcon icon, string label, int panel_max_height = 0) {
        anim_id = _next_anim_id++;
        this.icon = icon;
        this.text = label;
        this.width = icon.get_width();
        this.panel_max_height = panel_max_height;
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

    // Call from IClickable.mouse_down() in subclass to toggle panel open/close
    protected void handle_icon_click() {
        if (panel_max_height > 0) {
            opened = !opened;
            int target = opened ? panel_max_height : 0;
            animations.add(new Transition1D(anim_id, &panel_height, target, 0.2d));
            redraw = true;
        }
    }

    protected void close_panel() {
        if (opened) {
            opened = false;
            animations.add(new Transition1D(anim_id, &panel_height, 0, 0.2d));
            redraw = true;
        }
    }

    public virtual void render(Context ctx) {
        icon.render(ctx);
        if (panel_height > 0) {
            render_panel(ctx);
        }
    }

    // Override in subclasses to draw panel popup content
    protected virtual void render_panel(Context ctx) {}
}
