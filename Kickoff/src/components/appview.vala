using DrawKit;
using WLHooks;
using GLES2;

public class AppView {
    public string name;
    public GLuint tex;

    private bool hovered;
    private bool clicked;
    
    private int icon_offset_x;

    private int original_x;
    private int original_y;

    private int grid_x;
    private int grid_y;

    private int width;
    private int height;

    private unowned AppEntry app;

    public AppView(int x, int y){
        height = 15 + ICON_SIZE + 2*ICON_HOVER_PADDING;
        original_x = x;
        original_y = y;
        grid_x = x;
        grid_y = y;
    }

    public void set_properties(DrawKit.Context ctx, AppEntry app){
        this.name = app.short_name;
        this.tex = app.tex;
        this.app = app;

        width = max(ICON_SIZE, ctx.width_of(name, 20)) + 2*ICON_HOVER_PADDING;
        icon_offset_x = (width-ICON_SIZE) / 2;

        grid_x = original_x - (width/2);
    }

    private int max (int a, int b){ return (a>b)?a:b;}

    public void mouse_up (){
        clicked = false;
        if(hovered) {
            app.launch_app();
        };
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

            ctx.draw_rect_rounded(
                grid_x, 
                grid_y, 
                width,
                height, 
                15.0f,
                clicked ? clicked_color : hovered_color);
        }

        ctx.draw_texture(tex, grid_x+icon_offset_x, grid_y+ICON_HOVER_PADDING, ICON_SIZE, ICON_SIZE);
        ctx.draw_text(name, grid_x + width/2, grid_y + ICON_SIZE + 2*ICON_HOVER_PADDING+5, 20, {1,1,1,1});
    }
}