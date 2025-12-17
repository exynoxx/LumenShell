using DrawKit;
using WLHooks;
using GLES2;

public class AppEntry {
    private string name;
    private string name_short;
    private string icon_path;
    private string exec;
    private GLuint texture_id;
    private bool texture_loaded;

    private bool hovered;
    private bool clicked;
    
    private int icon_offset_x;
    private int grid_x;
    private int grid_y;

    private int width;
    private int height;

    private int max(int a, int b) {
        return a > b ? a : b;
    }

    public AppEntry(DrawKit.Context ctx, string name, string icon_path, string exec, int x, int y){
        this.name = name;
        this.name_short = name.char_count() > 20 ? name.substring(0, 20) + "..." : name;
        this.icon_path = icon_path;
        this.exec = exec;

        width = max(ICON_SIZE, ctx.width_of(name_short, 20)) + 2*ICON_HOVER_PADDING;
        icon_offset_x = (width-ICON_SIZE) / 2;
        height = 15 + ICON_SIZE + 2*ICON_HOVER_PADDING;

        grid_x = x - (width/2);
        grid_y = y;
    }

    public void mouse_up (){
        clicked = false;
        if(hovered) {
            //launch_app()
            //Main.animations.add(new MoveTransition(this, 10,10, 0.9));
        };
        Main.queue_redraw();
    }

    public void mouse_down(){
        if(hovered) {
            if(!clicked) Main.queue_redraw();
            clicked = true;
        }
    }

    public void mouse_move(double mouse_x, double mouse_y){
        int x = grid_x;
        int y = grid_y;
        int w = grid_x + width;
        int h = grid_y + height;
        
        var hover_initial = hovered;

        hovered = (mouse_x >= x && mouse_x <= w && mouse_y >= y && mouse_y <= h);
        if(hovered != hover_initial) Main.queue_redraw();
    }

    public void render(Context ctx){

        if (hovered) {

            const Color hovered_color = { 1.0f, 1.0f, 1.0f, 0.3f };
            const Color clicked_color = { 0.2f, 0.2f, 0.2f, 0.7f };

            ctx.dk_draw_rect_rounded(
                grid_x, 
                grid_y, 
                width,
                height, 
                15.0f,
                clicked ? clicked_color : hovered_color);
        }

        // Load texture on demand
        if (!texture_loaded) {
            var tex = ImageUtils.Upload_texture(icon_path, ICON_SIZE);
            texture_id = tex;
            texture_loaded = true;
        }
        
        // Draw icon or placeholder
        if (texture_id > 0) {
            ctx.draw_texture(texture_id, grid_x+icon_offset_x, grid_y+ICON_HOVER_PADDING, ICON_SIZE, ICON_SIZE);
        } else {
            ctx.draw_rect(grid_x+icon_offset_x, grid_y, ICON_SIZE, ICON_SIZE, { 1f, 1f, 1f, 1.0f });
        }

        //label
        ctx.draw_text(name_short, grid_x + width/2, grid_y + ICON_SIZE + 2*ICON_HOVER_PADDING+5, 20);
    }

    private void launch_app() {
        stdout.printf("Launching: %s (%s)\n", name, exec);
        
        try {
            Process.spawn_command_line_async(exec);
        } catch (SpawnError e) {
            stderr.printf("Failed to launch %s: %s\n", name, e.message);
        }
    }
}