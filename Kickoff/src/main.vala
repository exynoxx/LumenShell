using DrawKit;
using WLUnstable;
using GLES2;

const int GRID_COLS = 6;
const int ICON_SIZE = 96;
const int ICON_PADDING = 40;
const int TOP_MARGIN = 80;

struct AppEntry {
    string name;
    string icon_path;
    string exec;
    GLuint texture_id;
    bool texture_loaded;
    int grid_x;
    int grid_y;
}

class AppLauncher {

    private bool mouse_clicked = false;
    public bool redraw = true;

    private AppEntry[] apps;
    private int hovered_index = -1;
    private int screen_width;
    private int screen_height;
    private int start_x;
    private int start_y;

    public AppLauncher(int width, int height) {
        screen_width = width;
        screen_height = height;
        
        // Calculate starting position to center the grid
        start_x = 50;
        start_y = TOP_MARGIN;
        
        calculate_grid_positions();
    }

    private void mouse_down() => clicked = true;
    private void mouse_up() => clicked = false;

    private int mouse_move(int mouse_x, int mouse_y) {
        for (int i = 0; i < apps.length; i++) {
            int x = apps[i].grid_x;
            int y = apps[i].grid_y;
            
            if (mouse_x >= x && mouse_x <= x + ICON_SIZE &&
                mouse_y >= y && mouse_y <= y + ICON_SIZE) {
                return i;
            }
        }

        /*  var box_x = box.x;
            var box_y = box.y;
            var oldval = box.hovered;
            box.hovered = (
                x >= box_x && 
                x <= box_x + box_width &&
                y >= box_y && 
                y <= box_y + box_height);

            if(box.hovered != oldval) redraw = true;
            box_x += box_width;  */
        return -1;
    }

    private void calculate_grid_positions() {
        for (int i = 0; i < apps.length; i++) {
            int row = i / GRID_COLS;
            int col = i % GRID_COLS;
            
            apps[i].grid_x = start_x + col * (ICON_SIZE + ICON_PADDING);
            apps[i].grid_y = start_y + row * (ICON_SIZE + ICON_PADDING);
        }
    }

    public void render() {
        ctx.begin_frame();
        
        int visible_apps = int.min(apps.length, 48); // Limit for performance
        
        for (int i = 0; i < visible_apps; i++) {
            // Load texture on demand
            if (!apps[i].texture_loaded) {
                load_icon_texture(ref apps[i]);
            }
            
            // Draw icon or placeholder
            if (apps[i].texture_id > 0) {
                ctx.draw_texture(apps[i].texture_id, 
                               apps[i].grid_x, 
                               apps[i].grid_y, 
                               ICON_SIZE, 
                               ICON_SIZE);
            } else {
                // Placeholder colored rect
                Color placeholder_color = { 0.3f, 0.3f, 0.3f, 1.0f };
                ctx.draw_rect(apps[i].grid_x, 
                            apps[i].grid_y, 
                            ICON_SIZE, 
                            ICON_SIZE, 
                            placeholder_color);
            }
            
            // Highlight if hovered
            if (i == hovered_index) {
                Color highlight_color = { 1.0f, 1.0f, 1.0f, 0.3f };
                ctx.draw_rect(apps[i].grid_x - 4, 
                            apps[i].grid_y - 4, 
                            ICON_SIZE + 8, 
                            ICON_SIZE + 8, 
                            highlight_color);
            }
        }
        
        // Handle mouse interaction
        var mouse_info = seat_mouse_info();
        int mx = (int)mouse_info->mouse_x;
        int my = (int)mouse_info->mouse_y;
        
        hovered_index = check_hover(mx, my);
        
        if (mouse_clicked && hovered_index >= 0) {
            launch_app(hovered_index);
        }
        
        mouse_clicked = false;
        
        ctx.end_frame();
    }

    private void launch_app(int index) {
        if (index < 0 || index >= apps.length) return;
        
        string exec = apps[index].exec;
        // Remove field codes like %f, %F, %u, %U
        exec = exec.replace("%f", "").replace("%F", "")
                   .replace("%u", "").replace("%U", "")
                   .replace("%i", "").replace("%c", "")
                   .strip();
        
        stdout.printf("Launching: %s (%s)\n", apps[index].name, exec);
        
        try {
            Process.spawn_command_line_async(exec);
        } catch (SpawnError e) {
            stderr.printf("Failed to launch %s: %s\n", apps[index].name, e.message);
        }
    }
}

static AppLauncher? launcher = null;

public static int main(string[] args) {

    layncher = new AppLauncher();

    WLUnstable.register_on_mouse_down(layncher.mouse_down);
    WLUnstable.register_on_mouse_up(layncher.mouse_up);
    WLUnstable.register_on_mouse_motion(layncher.mouse_move);

    WLUnstable.init("Kickoff-overlay", 0, 0, TOP | BOTTOM | LEFT | RIGHT, false);

    var ctx = new DrawKit.Context(width, height);
    ctx.set_bg_color(DrawKit.Color(){ 0.15f, 0.15f, 0.15f, 0.95f });
    
    while (WLUnstable.display_dispatch_blocking() != -1) {
        
        if(layncher.redraw){
            layncher.render();
            WLUnstable.swap_buffers();
            layncher.redraw = false;
        }
    }

    return 0;
}