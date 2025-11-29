using DrawKit;
using WLUnstable;
using GLES2;

namespace Main {

    const int GRID_COLS = 6;
    const int GRID_ROWS = 4;
    const int ICON_SIZE = 96;
    const int ICON_HOVER_PADDING = 8;
    const int PADDING_EDGES = 100;
    
    struct AppEntry {
        string name;
        string icon_path;
        string exec;
        GLuint texture_id;
        bool texture_loaded;
        int grid_x;
        int grid_y;
        bool hovered;
    }
    
    class AppLauncher {
    
        DrawKit.Context ctx;

        private int hovered_index = -1;
        private bool clicked = false;
        public bool redraw = true;
    
        private AppEntry[] apps;
        private int visible_apps;
        private int screen_width;
        private int screen_height;
        private int padding_h;
        private int padding_v;
    
        public AppLauncher(int width, int height) {
            screen_width = width;
            screen_height = height;
    
            ctx = new DrawKit.Context(/*  size.width, size.height  */1920, 1080);
            ctx.set_bg_color(DrawKit.Color(){ r = 0, g =  0, b = 0, a = 0.70f });

            int gaps_h = GRID_COLS + 1;
            int gaps_v = GRID_ROWS + 1;

            //TODO KDE is 2 DPI
            padding_h = (width - GRID_COLS*ICON_SIZE - 3*PADDING_EDGES) / gaps_h;
            padding_v = (height - GRID_ROWS*ICON_SIZE - 3*PADDING_EDGES) / gaps_v;

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

            visible_apps = int.min(apps.length, GRID_COLS*GRID_ROWS);

            calculate_grid_positions();
        }

        private void calculate_grid_positions() {
            
            for (int i = 0; i < visible_apps; i++) {
                int row = i / GRID_COLS;
                int col = i % GRID_COLS;
                
                apps[i].grid_x = PADDING_EDGES + padding_h * col + col * ICON_SIZE;
                apps[i].grid_y = PADDING_EDGES + padding_v * row + row * ICON_SIZE;
            }
        }
    
        public void mouse_down() {
            clicked = true;
        }
        public void mouse_up() {
            clicked = false;
        }
    
        public void mouse_move(double mouse_x, double mouse_y) {
            for (int i = 0; i < visible_apps; i++) {
                int x = apps[i].grid_x-ICON_HOVER_PADDING;
                int y = apps[i].grid_y-ICON_HOVER_PADDING;
                int w = apps[i].grid_x + ICON_SIZE + 2*ICON_HOVER_PADDING;
                int h = apps[i].grid_y + ICON_SIZE + 2*ICON_HOVER_PADDING;
                
                var before = apps[i].hovered;
                apps[i].hovered = (mouse_x >= x && mouse_x <= w && mouse_y >= y && mouse_y <= h);
                if(apps[i].hovered != before) redraw = true;
            }
        }
    
        public void render() {
            ctx.begin_frame();
            
            for (int i = 0; i < visible_apps; i++) {

                // Highlight if hovered
                if (apps[i].hovered) {
                    ctx.dk_draw_rect_rounded(
                        apps[i].grid_x - ICON_HOVER_PADDING, 
                        apps[i].grid_y - ICON_HOVER_PADDING, 
                        ICON_SIZE + 2*ICON_HOVER_PADDING,
                        ICON_SIZE + 2*ICON_HOVER_PADDING, 
                        15.0f,
                        { 1.0f, 1.0f, 1.0f, 0.3f });
                }

                // Load texture on demand
                if (!apps[i].texture_loaded) {
                    var tex = ImageUtils.Upload_texture(apps[i].icon_path, ICON_SIZE);
                    apps[i].texture_id = tex;
                    apps[i].texture_loaded = true;
                }
                
                // Draw icon or placeholder
                if (apps[i].texture_id > 0) {
                    ctx.draw_texture(apps[i].texture_id, apps[i].grid_x, apps[i].grid_y, ICON_SIZE, ICON_SIZE);
                } else {
                    ctx.draw_rect(apps[i].grid_x, apps[i].grid_y, ICON_SIZE, ICON_SIZE, { 1f, 1f, 1f, 1.0f });
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
    
        WLUnstable.init_layer_shell("Kickoff-overlay", 1920, 1080, UP | LEFT | RIGHT | DOWN, false);
    
        var size = WLUnstable.get_layer_shell_size();
        print("layer shell size: %i %i\n", size.width, size.height);

        launcher = new AppLauncher(/*  size.width, size.height  */1920, 1080);
    
        WLUnstable.register_on_mouse_down(() => launcher.mouse_down());
        WLUnstable.register_on_mouse_up(() => launcher.mouse_up());
        WLUnstable.register_on_mouse_motion((x,y)=>launcher.mouse_move(x,y)); //fix double
        WLUnstable.register_on_key_down(key=> {
            if(key == 65307){
                Process.exit (0);
            }
            print("Key %d\n", (int) key);
        });
        
        while (WLUnstable.display_dispatch_blocking() != -1) {
            
            if(launcher.redraw){
                launcher.render();
                WLUnstable.swap_buffers();
                launcher.redraw = false;
            }
        }
    
        return 0;
    }
}
