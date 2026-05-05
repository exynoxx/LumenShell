using DrawKit;
using GLES2;
/*  DEVICE  TYPE      STATE      CONNECTION
wlp2s0  wifi      connected  HomeWiFi
eth0    ethernet  unavailable --


# Overall connectivity state
nmcli networking connectivity
# Wi-Fi status
nmcli device status*/

public const int FONT_SIZE = 16;

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
        var wifi = new WifiTray(ctx);
        var battery = new BatteryTray(ctx);
        var clock = new Clock(ctx);
        var exit = new ExitTray(ctx);

        trays += wifi;
        trays += battery;
        trays += clock;
        trays += exit;

        base_width = width = get_children_width();

        this.x = screen_width - width - MARGIN_RIGHT;
        set_children_positions();
        expand_animation = new TransitionEmpty();
    }

    private int get_children_width(){
        var w = trays.length*SPACING;
        foreach(var t in trays) 
            w += t.get_width();
        return w;
    }

    private void set_children_positions(){
        var current_x = this.x + SPACING;
        foreach (var t in trays){
            t.set_position(current_x, TRAY_Y);
            current_x += t.get_width() + SPACING;
        }
    }


    public void on_mouse_down(){
        foreach(var t in trays)
            if (t is IClickable)
                (t as IClickable).mouse_down();
    }

    public void on_mouse_up(){
        foreach(var t in trays)
            if (t is IClickable)
                (t as IClickable).mouse_up();
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
                if (tray is IHoverable)
                    (tray as IHoverable).mouse_motion(mouse_x,mouse_y);
        }

        if (hovered && !hover_initial) 
            expand();

        if(!hovered && hover_initial)
            contract();
        
    }

    private void expand(){
        /*  var max_width = 0;
        foreach(var t in trays) 
            max_width += t.get_max_width();

        expand_animation = new Transition1D(0, &width, max_width, 1d);
        animations.add(expand_animation);
  */
        foreach(var t in trays) 
            if (t is IExpandable)
                (t as IExpandable).expand();

        //var height_animation = new Transition1D(1, &height, TRAY_MAX_HEIGHT, 1d);
        //animations.add(height_animation);
    }

    private void contract(){
        expand_animation = new Transition1D(0, &width, base_width, 1d);
        animations.add(expand_animation);
        //var height_animation = new Transition1D(1, &height, TRAY_HEIGHT, 1d);
        //animations.add(height_animation);
        foreach(var t in trays) 
            if (t is IExpandable)
                (t as IExpandable).contract();
    }

    public void on_mouse_leave(){
        if(width > base_width){
            contract();
        }
        on_mouse_motion(-1,-1);
        redraw = true;
    }

    public void render(){
        if(animations.has_active){
            width = get_children_width();
            this.x = screen_width - width - MARGIN_RIGHT;
            //this.y = HEIGHT - height - MARGIN_TOP;
            //set_children_positions();
        }

        ctx.draw_rect_rounded(this.x, this.y, width, height, 24, {0.15f,0.15f,0.15f,1});
        foreach(var t in trays){
            t.render(ctx);
        }
    }

}