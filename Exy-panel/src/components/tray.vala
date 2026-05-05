using DrawKit;
using GLES2;

public const int FONT_SIZE = 16;

public class Tray {

    public const int MARGIN_RIGHT = 20;
    public const int TRAY_HEIGHT = EXCLUSIVE_HEIGHT - 12;
    public const int MARGIN_TOP = (EXCLUSIVE_HEIGHT - TRAY_HEIGHT)/2;
    public const int TRAY_Y = HEIGHT - TRAY_HEIGHT - MARGIN_TOP;
    public const int SPACING = 20;

    private unowned Context ctx;
    private int screen_width;

    private ITray[] trays;

    private int width;
    private int x;
    private int y;

    public Tray(Context ctx, int screen_width){
        this.ctx = ctx;
        this.screen_width = screen_width;
        this.y = TRAY_Y;

        var wifi    = new WifiTray(ctx);
        var battery = new BatteryTray(ctx);
        var clock   = new Clock(ctx);
        var exit    = new ExitTray(ctx);

        trays += wifi;
        trays += battery;
        trays += clock;
        trays += exit;

        // initial layout so positions are valid before first render
        layout_children();
    }

    // Layout trays right-to-left so the rightmost tray is anchored to the screen
    // right edge. When a tray expands (width grows), only trays to its LEFT shift
    // further left — trays to its right are unaffected.
    private void layout_children(){
        var current_x = screen_width - MARGIN_RIGHT;

        for (int i = trays.length - 1; i >= 0; i--) {
            current_x -= trays[i].get_width() + SPACING;
            trays[i].set_position(current_x, TRAY_Y);
        }

        // Update container bounding box to enclose all children
        this.x     = current_x - SPACING;
        this.width = screen_width - MARGIN_RIGHT - this.x;
    }

    public void on_mouse_down(){
        foreach (var t in trays)
            if (t is IClickable)
                ((IClickable) t).mouse_down();
    }

    public void on_mouse_up(){
        foreach (var t in trays)
            if (t is IClickable)
                ((IClickable) t).mouse_up();
    }

    public void on_mouse_motion(int mouse_x, int mouse_y){
        // Forward motion to each tray; IHoverable items auto-expand/contract themselves
        foreach (var tray in trays)
            if (tray is IHoverable)
                ((IHoverable) tray).mouse_motion(mouse_x, mouse_y);
    }

    public void on_mouse_leave(){
        // Simulate mouse moving far off-screen so every hoverable contracts
        on_mouse_motion(-1, -1);
        redraw = true;
    }

    public void render(){
        // Re-layout every frame so expanding trays push siblings left smoothly
        layout_children();

        ctx.draw_rect_rounded(this.x, this.y, width, TRAY_HEIGHT, 24, {0.15f, 0.15f, 0.15f, 1});

        foreach (var t in trays)
            t.render(ctx);
    }

}
