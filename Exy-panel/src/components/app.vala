using GLES2;
using DrawKit;

public class App {
    public const int WIDTH = 70;
    public const int HEIGHT = 55;

    public int order;
    public uint id;
    public string app_id;
    public string title;
    public GLuint tex;
    public bool hovered;
    public bool clicked;
    public int x;
    public int y;
    public int tex_x;
    public int tex_y;

    const int padding_side = (App.WIDTH - 32)/2;
    const int padding_top = (App.HEIGHT - 32)/2;

    public App (uint id, string app_id, string title, int order){
        this.id = id;
        this.app_id = app_id;
        this.title = title;
        this.y = 0;

        reset_order(order);
        load_icon();
    }

    public void reset_order(int i){
        this.order = i;
        this.x = i*WIDTH+2; //2 from seperator
        this.tex_x = x + padding_side;
        this.tex_y = y + padding_top;
    }

    public void mouse_motion(int x, int y){
        var box_x = this.x;
        var box_y = this.y;
        var oldval = hovered;
        hovered = (
            x >= box_x && 
            x <= box_x + WIDTH &&
            y >= box_y && 
            y <= box_y + HEIGHT);

        if(hovered != oldval) redraw = true;
    }

    public void render(Context ctx){
        var color = Color(){r=1,g=1,b=1,a=0f};
        if (hovered) color.a = 0.2f; 

        ctx.draw_rect(this.x, this.y, WIDTH, HEIGHT, color);
        ctx.draw_texture(tex, tex_x, tex_y, 32, 32);
    }

    public void on_click(){

        if(order == 0){
            Process.spawn_command_line_sync("/home/nicholas/Dokumenter/layer-shell-experiments/Kickoff/main");
        } 
    
        WLHooks.toplevel_activate_by_id(id);
        redraw = true;
    }

    public void free(){
        DrawKit.texture_free(tex);
    }

    private void load_icon(){
        if (order == 0){
            var image = DrawKit.image_from_svg("/home/nicholas/Dokumenter/layer-shell-experiments/Exy-panel/src/res/app.svg",32,32);
            if(image == null){
                print("Launcher icon not found");
                return;
            }

            tex = DrawKit.texture_upload(*image);
            return;
        }

        var icon_path = Utils.get_icon_path_from_app_id(app_id);
        if(icon_path.contains(".svg")){
            var image = DrawKit.image_from_svg(icon_path,32,32);
            tex = DrawKit.texture_upload(*image);
        } else{
            var image = DrawKit.image_load(icon_path);
            tex = DrawKit.texture_upload(image);
        }
    }
}