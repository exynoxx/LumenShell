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
    private int base_width;

    private int width;
    private int height;
    private int x;
    private int y;
    private bool hovered;

    private Transition expand_animation;

    public Tray(Context ctx, int screen_width){
        this.ctx = ctx;
        this.screen_width = screen_width;
        this.y = TRAY_Y;
        this.height = TRAY_HEIGHT;

        //calc width
        var wifi = new WifiTray();
        var battery = new BatteryTray();
        var clock = new Clock(ctx);
        var exit = new ExitTray();

        trays += wifi;
        trays += battery;
        trays += clock;
        trays += exit;

        foreach(var t in trays) 
            base_width += t.get_width();

        base_width+=4*SPACING;
        width = base_width;

        //calc x's
        this.x = screen_width - width - MARGIN_RIGHT;

        var current_x = this.x + SPACING;
        foreach (var tray in trays){
            tray.set_position(current_x, TRAY_Y);
            current_x += tray.get_width() + SPACING;
        }

        expand_animation = new TransitionEmpty();
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
        expand_animation = new Transition1D(0, &width, 400, 1d);
        var height_animation = new Transition1D(1, &height, TRAY_MAX_HEIGHT, 1d);
        animations.add(expand_animation);
        animations.add(height_animation);
    }

    private void contract(){
        expand_animation = new Transition1D(0, &width, base_width, 1d);
        var height_animation = new Transition1D(1, &height, TRAY_HEIGHT, 1d);
        animations.add(expand_animation);
        animations.add(height_animation);
    }

    public void on_mouse_leave(){
        if(width > base_width){
            contract();
        }
        redraw = true;
    }

    public void render(){
        if(!expand_animation.finished){
            this.x = screen_width - width - MARGIN_RIGHT;
            this.y = HEIGHT - height - MARGIN_TOP;
        }

        ctx.draw_rect_rounded(this.x, this.y, width, height, 24, {0.15f,0.15f,0.15f,1});
        foreach(var t in trays){
            t.render(ctx);
        }
    }

}