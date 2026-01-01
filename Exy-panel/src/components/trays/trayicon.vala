using DrawKit;
using GLES2;

public interface ITray {
    public abstract int get_width();
    public abstract void set_position(int x, int y);
    public abstract void mouse_down();
    public abstract void mouse_up();
    public abstract void mouse_motion(int mouse_x, int mouse_y);
}

public abstract class TrayIcon : ITray {

    private const string base_path = "/home/nicholas/Dokumenter/layer-shell-experiments/Exy-panel/src/res/";
    private const int ICON_SIZE = 32;
    private const int MARGIN_TOP = (Tray.TRAY_HEIGHT - ICON_SIZE)/2;

    private GLuint tex;
    protected bool hovered;
    
    private int x;
    private int y;
    private int hover_x;
    private int hover_y;

    private int width;

    protected TrayIcon(string icon){
        load(icon);
        width = 24*2;
    }

    public int get_width() {
        return 24*2;
    }

    public void set_position(int x, int y){
        this.x = x;
        this.y = y + MARGIN_TOP;
        this.hover_x = this.x + ICON_SIZE/2;
        this.hover_y = this.y + ICON_SIZE/2;
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

    public void mouse_motion(int mouse_x, int mouse_y){
        int w = x + width;
        int h = y + width;
        
        var hover_initial = hovered;

        hovered = (mouse_x >= x && mouse_x <= w && mouse_y >= y && mouse_y <= h);
        if(hovered != hover_initial) 
            redraw = true;
    }

    public abstract void mouse_down();
    public abstract void mouse_up();

    public void render(Context ctx){
        
        if(hovered){
            ctx.draw_circle(hover_x, hover_y, 24, {1,1,1,1});
            ctx.set_tex_color({0,0,0,1});
            ctx.draw_texture(tex, x, y, ICON_SIZE, ICON_SIZE);
            ctx.set_tex_color({1,1,1,1});
            return;

        } 

        ctx.draw_texture(tex, x, y, ICON_SIZE, ICON_SIZE);
    }
}

public class WifiTray : TrayIcon {

    public WifiTray() {
        base ("wifi");
    }

    public override void mouse_down(){

    }
    public override void mouse_up(){

    }
}

public class ExitTray : TrayIcon {

    public ExitTray() {
        base ("close");
    }

    public override void mouse_down(){
        if(base.hovered) 
            Process.spawn_command_line_async("pkill wayfire");
    }
    public override void mouse_up(){

    }
}

public class BatteryTray : TrayIcon {

    public BatteryTray() {
        base ("mid");
    }

    public override void mouse_down(){
    }
    public override void mouse_up(){

    }
}
