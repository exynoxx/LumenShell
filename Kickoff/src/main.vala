using DrawKit;
using WLUnstable;
using GLES2;

namespace Main {

    const int GRID_COLS = 6;
    const int GRID_ROWS = 4;
    const int ICON_SIZE = 56;
    const int PADDING_EDGES = 100;
    
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
    
        private int hovered_index = -1;
        private bool mouse_clicked = false;
        public bool redraw = true;
    
        private AppEntry[] apps;
        private int screen_width;
        private int screen_height;
        private int padding_h;
        private int padding_v;
    
        public AppLauncher(int width, int height) {
            screen_width = width;
            screen_height = height;
    
            padding_h = (width - PADDING_EDGES*2 - GRID_COLS*ICON_SIZE) / 2;
            padding_v = (height - PADDING_EDGES*2 - GRID_ROWS*ICON_SIZE) / 2;
            
            calculate_grid_positions();
        }
    
        private void mouse_down() {
            clicked = true;
        }
        private void mouse_up() {
            clicked = false;
        }
    
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
                
                apps[i].grid_x = PADDING_EDGES + padding_h + col * (ICON_SIZE + padding_h*2);
                apps[i].grid_y = PADDING_EDGES + padding_v + row * (ICON_SIZE + padding_v*2);
            }
        }
    
        public void render() {
            ctx.begin_frame();
            
            int visible_apps = int.min(apps.length, GRID_COLS*GRID_ROWS);
            
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
    
    static int main(string[] args) {
    
        WLUnstable.init_layer_shell("Kickoff-overlay", 0, 0, UP | DOWN | LEFT | RIGHT, false);
    
        var size = WLUnstable.get_layer_shell_size();
        var ctx = new DrawKit.Context(size.width, size.height);
        ctx.set_bg_color(DrawKit.Color(){ r = 0.15f, g =  0.15f, b = 0.15f, a = 0.95f });
    
        layncher = new AppLauncher(size.width, size.height);
    
        WLUnstable.register_on_mouse_down(() => layncher.mouse_down());
        WLUnstable.register_on_mouse_up(() => layncher.mouse_up());
        WLUnstable.register_on_mouse_motion((x,y)=>layncher.mouse_move(x,y)); //fix double
        
        while (WLUnstable.display_dispatch_blocking() != -1) {
            
            if(layncher.redraw){
                layncher.render();
                WLUnstable.swap_buffers();
                layncher.redraw = false;
            }
        }
    
        return 0;
    }
}
