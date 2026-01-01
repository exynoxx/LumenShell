using DrawKit;
using GLES2;

public class TrayIcon {

    private const string base_path = "/home/nicholas/Dokumenter/layer-shell-experiments/Exy-panel/src/res/";
    private const int ICON_SIZE = 32;

    private GLuint tex;
    private int y;
    private bool hovered;
    
    private int x;
    public int width {get; private set;}

    public int global_x;
    public int global_width;

    public TrayIcon(int x, int y, string icon){
        this.x = x;
        this.y = y+8;
        load(icon);
        width = ICON_SIZE;
    }

    public void set_position(int global_x, int global_width, int local_x){
        this.global_x = global_x;
        this.global_width = global_width;
        this.x = local_x;
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
        print("hovered %b\n", hovered);
        if(hovered != hover_initial) 
            redraw = true;
    }

    public void render(Context ctx){
        
        if(hovered){
            ctx.stencil_push();

            //mask
            ctx.draw_rect_rounded(global_x, Tray.MARGIN_TOP, global_width, Tray.TRAY_HEIGHT, 24, {1,1,1,1});

            ctx.stencil_apply();

            ctx.draw_rect(this.x - Tray.SPACING, Tray.MARGIN_TOP, 100, Tray.TRAY_HEIGHT, {1,1,1,1});

            ctx.stencil_pop();
        }
        
        ctx.draw_texture(tex, x, y, ICON_SIZE, ICON_SIZE);
    }
}