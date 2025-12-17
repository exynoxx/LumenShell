using DrawKit;
using WLHooks;
using GLES2;

const int GRID_COLS = 6;
const int GRID_ROWS = 4;
const int ICON_SIZE = 96;
const int ICON_HOVER_PADDING = 8;
const int PADDING_EDGES_Y = 80;
const int PADDING_EDGES_X = 150;

public class AppLauncher {

    DrawKit.Context ctx;

    private AppEntry[] apps;
    private int screen_width;
    private int screen_height;
    
    private int screen_center_x;
    private int screen_center_y;
    
    private float page_x;
    private int active_page;

    private float bg_a = 0;
    private float grid_zoom[16];
    private float grid_zoom_factor = 10;

    public AppLauncher(int width, int height) {
        screen_width = width;
        screen_height = height;

        screen_center_x = screen_width/2;
        screen_center_y = screen_height/2;

        ctx = Context.Init_with_groups(width, height, 3);

        var icon_theme = SystemUtils.get_current_theme();
        var icon_paths = IconUtils.find_icon_paths(icon_theme, 96);
        print("using icon theme: %s. Num icons: %i\n", icon_theme, icon_paths.size);

        var desktop_files = SystemUtils.get_desktop_files();
        print("Apps %i\n", desktop_files.length);

        var grid_positions = MathUtils.Calculate_grid_positions(screen_width, screen_height, desktop_files.length);

        int i = 0;
        foreach (var desktop in desktop_files){
            var entries = ConfigUtils.parse(desktop, "Desktop Entry");

            if (entries["Icon"] == null || entries["Exec"] == null || entries["Name"] == null) continue;

            var name = entries["Name"];
            var icon = entries["Icon"];
            var exec = entries["Exec"]
                .replace("%f", "")
                .replace("%F", "")
                .replace("%u", "")
                .replace("%U", "")
                .replace("%i", "")
                .replace("%c", "")
                .strip();

            if(!icon_paths.has_key(icon)){
                continue;
            }

            var icon_path = icon_paths[icon];
            var pos = grid_positions[i++];
            apps += new AppEntry(ctx, name, icon_path, exec, pos.x, pos.y);

            //if(i>GRID_COLS*GRID_ROWS) break;
        }

        print("Apps after filter %i\n", apps.length);

        Main.animations.add(new Transition1D(0, &bg_a, 0.9f, 3));
        Main.animations.add(new Transition1D(1, &grid_zoom_factor, 1, 1.5));
        //Main.animations.add(new Transition1Df(&grid_zoom_factor, 1, 3));
        /*  Main.animations.add(new Transition1D(&page_x, 0, 3));
        Main.animations.add(new Transition1D(&page_y, 0, 3));  */
    }

    public void mouse_down() {
        foreach (var app in apps)
            app.mouse_down();
    }
    public void mouse_up() {
        foreach (var app in apps)
            app.mouse_up();
    }

    public void key_down(uint64 key){
        if(key == 65363){
            active_page--;
            Main.animations.add(new Transition1D(2, &page_x, active_page*screen_width, 1.5));
        }

        if(key == 65361){
            active_page++;
            Main.animations.add(new Transition1D(3, &page_x, active_page*screen_width, 1.5));
        }
    }

    public void mouse_move(double mouse_x, double mouse_y) {
        foreach (var app in apps)
            app.mouse_move(mouse_x, mouse_y);
    }
    
    public void render() {
        
        //translate(x,y) * zoom(factor) * translate(-x,-y)
        grid_zoom[0] = grid_zoom_factor;
        grid_zoom[5] = grid_zoom_factor;
        grid_zoom[10] = 1;
        grid_zoom[12] = screen_center_x * (1 - grid_zoom_factor);
        grid_zoom[13] = screen_center_y * (1 - grid_zoom_factor);
        grid_zoom[15] = 1;

        ctx.set_bg_color(DrawKit.Color(){ r = 0, g =  0, b = 0, a = bg_a });
        ctx.begin_frame();
        
        DrawKit.begin_group(1);
        DrawKit.begin_group(2);
        DrawKit.group_matrix(2,grid_zoom);
        DrawKit.group_location(1, (int)page_x, 0);
        foreach (var app in apps) {
            app.render(ctx);
        }
        DrawKit.end_group(1);
        DrawKit.end_group(2);

        //ctx.draw_rect(10,10,50,50,{1f,1f,1f,1f});

        int middle = (int) screen_width/2;
        int y = screen_height - 200;

        ctx.draw_circle(middle - 50,y, 15, {0.3f,0.3f,0.3f,1f});
        ctx.draw_circle(middle - 0,y, 15, {0.3f,0.3f,0.3f,1f});
        ctx.draw_circle(middle + 50,y, 15, {0.3f,0.3f,0.3f,1f});

        ctx.draw_text("1", middle - 50,y+5, 15);
        ctx.draw_text("2", middle - 0,y+5, 15);
        ctx.draw_text("3", middle + 50,y+5, 15);

        ctx.end_frame();
    }

    private static float[] create_zoom_matrix(float zoom_factor) {
        float[] matrix = new float[16];
        
        matrix[0] = zoom_factor;  // X scale
        matrix[5] = zoom_factor;  // Y scale
        matrix[10] = zoom_factor; // Z scale
        matrix[15] = 1.0f;        // W (homogeneous)
        
        return matrix;
    }
}