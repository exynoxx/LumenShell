using DrawKit;
using GLES2;
/*  DEVICE  TYPE      STATE      CONNECTION
wlp2s0  wifi      connected  HomeWiFi
eth0    ethernet  unavailable --


# Overall connectivity state
nmcli networking connectivity
# Wi-Fi status
nmcli device status*/

public class Tray {

    public const int MARGIN_RIGHT = 20;
    public const int TRAY_HEIGHT = EXCLUSIVE_HEIGHT - 12;
    public const int MARGIN_TOP = (EXCLUSIVE_HEIGHT - TRAY_HEIGHT)/2;
    public const int TRAY_Y = HEIGHT - TRAY_HEIGHT - MARGIN_TOP;
    public const int TRAY_MAX_HEIGHT = HEIGHT - MARGIN_TOP;
    public const int SPACING = 20;

    private unowned Context ctx;
    private int screen_width;

    private ITray[] trays;

    private int width;
    private int height;
    private int x;
    private int y;
    private bool hovered;

    public Tray(Context ctx, int screen_width){
        this.ctx = ctx;
        this.screen_width = screen_width;
        this.height = TRAY_HEIGHT;

        var wifi = new WifiTray();
        var battery = new BatteryTray();
        var clock = new Clock(ctx);
        var exit = new ExitTray();

        trays += wifi;
        trays += battery;
        trays += clock;
        trays += exit;

        // Initial layout (recalculate() will keep it up to date every frame).
        recalculate();
    }


    public void on_mouse_down(){
        foreach(var t in trays)
            t.mouse_down();
    }

    public void on_mouse_up(){
        foreach(var t in trays)
            t.mouse_up();
    }
    
    public void on_mouse_motion(int mouse_x, int mouse_y){
        var hover_initial = hovered;

        hovered = (
            mouse_x >= this.x && 
            mouse_x <= this.x + width &&
            mouse_y >= this.y && 
            mouse_y <= this.y + height);

        if(hovered){
            foreach(var tray in trays)
                tray.mouse_motion(mouse_x,mouse_y);
        }

        if (hovered && !hover_initial) 
            expand();

        if(!hovered && hover_initial)
            contract();
        
    }

    private void expand(){
        animations.add(new Transition1D(1, &height, TRAY_MAX_HEIGHT, 1d));
    }

    private void contract(){
        animations.add(new Transition1D(1, &height, TRAY_HEIGHT, 1d));
    }

    public void on_mouse_leave(){
        contract();
        redraw = true;
    }

    // Recompute total width from current item widths and reposition all items.
    // Called every render frame so item expansion and contraction are reflected instantly.
    private void recalculate(){
        int total = 0;
        foreach(var t in trays)
            total += t.get_width();
        total += trays.length * SPACING;
        width = total;

        // Right-align the tray; left edge moves left as items expand.
        x = screen_width - width - MARGIN_RIGHT;
        // Tray container top; icons are always pinned to TRAY_Y.
        y = HEIGHT - height - MARGIN_TOP;

        var current_x = x + SPACING;
        foreach(var t in trays){
            t.set_position(current_x, TRAY_Y);
            current_x += t.get_width() + SPACING;
        }
    }

    public void render(){
        recalculate();

        ctx.draw_rect_rounded(this.x, this.y, width, height, 24, {0.15f,0.15f,0.15f,1});
        foreach(var t in trays){
            t.render(ctx);
        }
    }

}