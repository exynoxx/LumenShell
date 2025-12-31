using DrawKit;
using GLES2;
/*  DEVICE  TYPE      STATE      CONNECTION
wlp2s0  wifi      connected  HomeWiFi
eth0    ethernet  unavailable --


# Overall connectivity state
nmcli networking connectivity
# Wi-Fi status
nmcli device status*/

public class TrayIcon {

    private const string base_path = "/home/nicholas/Dokumenter/layer-shell-experiments/Exy-panel/src/res/";
    private const int ICON_SIZE = 36;

    private GLuint tex;
    private int y;
    
    public int x;
    public int width;

    public TrayIcon(int x, int y, string icon){
        this.x = x;
        this.y = y+6;
        load(icon);
        width = ICON_SIZE;
    }

    public void load(string icon){

        var path = Path.build_filename(base_path, icon+".svg");

        var image = DrawKit.image_from_svg(path,ICON_SIZE,ICON_SIZE);
        if(image == null){
            print("Launcher icon not found");
            return;
        }

        tex = DrawKit.texture_upload(*image);
    }

    public void free(){
        DrawKit.texture_free(tex);
    }

    public void render(Context ctx){/*  
        var color = Color(){r=1,g=1,b=1,a=0f};
        if (hovered) color.a = 0.2f; 

        ctx.draw_rect(this.x, this.y, WIDTH, HEIGHT, color);  */
        ctx.draw_texture(tex, x, y, ICON_SIZE, ICON_SIZE);
    }
}

public class Tray {

    private const int MARGIN_RIGHT = 20;
    private const int TRAY_HEIGHT = HEIGHT - 12;
    private const int MARGIN_TOP = (HEIGHT - TRAY_HEIGHT)/2;
    private const int SPACING = 20;

    private unowned Context ctx;
    private int screen_width;

    private TrayIcon[] trays;
    private int width;
    private int x;
    private int y;

    public Tray(Context ctx, int screen_width){
        this.ctx = ctx;
        this.screen_width = screen_width;
        this.y = MARGIN_TOP;

        //calc width
        string[] names = {"wifi", "mid", "close"};
        foreach (var name in names) {
            var tray = new TrayIcon(0, MARGIN_TOP, name);
            width += SPACING + tray.width;
            trays += tray;
        }
        width += SPACING/2;
        
        //calc x's
        this.x = screen_width - width - MARGIN_RIGHT;

        var current_x = this.x + SPACING;
        foreach (var tray in trays){
            tray.x = current_x;
            current_x += tray.width + SPACING;
        }
    }


    public void on_mouse_down(){
        
    }

    public void on_mouse_up(){
        
    }
    
    public void on_mouse_motion(int x, int y){
       
    }

    public void on_mouse_leave(){
        
        redraw = true;
    }

    public void render(){
        ctx.draw_rect_rounded(x, y, width, TRAY_HEIGHT, 24, {0.15f,0.15f,0.15f,1});
        foreach(var t in trays){
            t.render(ctx);
        }
    }

}