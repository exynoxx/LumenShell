using DrawKit;
using WLUnstable;
using GLES2;

namespace Main {

    const int GRID_COLS = 6;
    const int GRID_ROWS = 4;
    const int ICON_SIZE = 96;
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
        private bool clicked = false;
        public bool redraw = true;
    
        private AppEntry[] apps;
        private int screen_width;
        private int screen_height;
        private int padding_h;
        private int padding_v;
    
        public AppLauncher(int width, int height) {
            screen_width = width;
            screen_height = height;
    
            int gaps_h = GRID_COLS + 1;
            int gaps_v = GRID_ROWS + 1;

            padding_h = (width - GRID_COLS*ICON_SIZE-PADDING_EDGES*2) / (gaps_h);
            padding_v = (height - GRID_ROWS*ICON_SIZE-PADDING_EDGES*2) / (gaps_v);

            var icon_theme = SystemUtils.get_current_theme();
            var icon_paths = IconUtils.find_icon_paths(icon_theme, 96);
            print("using icon theme: %s. Num icons: %i\n", icon_theme, icon_paths.size);

            var desktop_files = SystemUtils.get_desktop_files();
            print("Apps %i\n", desktop_files.length);

            foreach (var desktop in desktop_files){
                var entries = ConfigUtils.parse(desktop, "Desktop Entry");
                var icon = entries["Icon"];
                var exec = entries["Exec"];
                var name = entries["Name"];

                //TODO rm has key later
                if(icon == null || !icon_paths.has_key(icon)){
                    continue;
                }

                var icon_path = icon_paths[icon];
                apps += AppEntry(){name = name, icon_path = icon_path, exec = exec};
            }

            calculate_grid_positions();
        }
    
        public void mouse_down() {
            clicked = true;
        }
        public void mouse_up() {
            clicked = false;
        }
    
        public void mouse_move(double mouse_x, double mouse_y) {
            for (int i = 0; i < apps.length; i++) {
                int x = apps[i].grid_x;
                int y = apps[i].grid_y;
                
                if (mouse_x >= x && mouse_x <= x + ICON_SIZE &&
                    mouse_y >= y && mouse_y <= y + ICON_SIZE) {
                    //return i;
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
            //return -1;
        }
    
        private void calculate_grid_positions() {
            
            for (int i = 0; i < apps.length; i++) {
                int row = i / GRID_COLS;
                int col = i % GRID_COLS;
                
                apps[i].grid_x = PADDING_EDGES + padding_h * col + col * ICON_SIZE;
                apps[i].grid_y = PADDING_EDGES + padding_v * row + row * ICON_SIZE;
            }
        }
    
        public void render(DrawKit.Context ctx) {
            ctx.begin_frame();
            
            int visible_apps = int.min(apps.length, GRID_COLS*GRID_ROWS);
            
            for (int i = 0; i < visible_apps; i++) {
                // Load texture on demand
                if (!apps[i].texture_loaded) {
                    var tex = ImageUtils.Upload_texture(apps[i].icon_path, ICON_SIZE);
                    apps[i].texture_id = tex;
                    apps[i].texture_loaded = true;
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
                    Color placeholder_color = { 1f, 1f, 1f, 1.0f };
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
    
        WLUnstable.init_layer_shell("Kickoff-overlay", 1920, 1080, UP | DOWN | LEFT | RIGHT, false);
    
        var size = WLUnstable.get_layer_shell_size();
        print("layer shell size: %i %i\n", size.width, size.height);

        var ctx = new DrawKit.Context(/*  size.width, size.height  */1920, 1080);
        ctx.set_bg_color(DrawKit.Color(){ r = 0, g =  0, b = 0, a = 0.50f });
    
        launcher = new AppLauncher(/*  size.width, size.height  */1920, 1080);
    
        WLUnstable.register_on_mouse_down(() => launcher.mouse_down());
        WLUnstable.register_on_mouse_up(() => launcher.mouse_up());
        WLUnstable.register_on_mouse_motion((x,y)=>launcher.mouse_move(x,y)); //fix double
        
        while (WLUnstable.display_dispatch_blocking() != -1) {
            
            if(launcher.redraw){
                launcher.render(ctx);
                WLUnstable.swap_buffers();
                launcher.redraw = false;
            }
        }
    
        return 0;
    }
}
