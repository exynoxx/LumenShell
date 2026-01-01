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
    public const int TRAY_HEIGHT = HEIGHT - 12;
    public const int MARGIN_TOP = (HEIGHT - TRAY_HEIGHT)/2;
    public const int SPACING = 20;

    private unowned Context ctx;
    private int screen_width;

    private TrayIcon[] trays;
    private int width;
    private int x;
    private int y;

    public Tray(Context ctx, int screen_width){
        this.ctx = ctx;
        this.screen_width = screen_width;

        //calc width
        string[] names = {"wifi", "mid", "close"};
        foreach (var name in names) {
            var tray = new TrayIcon(0, MARGIN_TOP, name);
            width += SPACING + tray.width;
            trays += tray;
        }
        width += SPACING;
        
        //calc x's
        this.x = screen_width - width - MARGIN_RIGHT;

        var current_x = this.x + SPACING;
        foreach (var tray in trays){
            tray.set_position(this.x, width, current_x);
            current_x += tray.width + SPACING;
        }
    }


    public void on_mouse_down(){
        
    }

    public void on_mouse_up(){
        
    }
    
    public void on_mouse_motion(int x, int y){
        foreach(var tray in trays){
            tray.mouse_motion(x,y);
        }
    }

    public void on_mouse_leave(){
        
        redraw = true;
    }

    public void render(){
        ctx.draw_rect_rounded(x, MARGIN_TOP, width, TRAY_HEIGHT, 24, {0.15f,0.15f,0.15f,1});
        foreach(var t in trays){
            t.render(ctx);
        }
    }

}