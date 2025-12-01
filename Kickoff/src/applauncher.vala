using DrawKit;
using WLUnstable;
using GLES2;

const int GRID_COLS = 6;
const int GRID_ROWS = 4;
const int ICON_SIZE = 96;
const int ICON_HOVER_PADDING = 8;
const int PADDING_EDGES = 100;

class AppEntry {
    private string name;
    private string name_short;
    private string icon_path;
    private  string exec;
    private  GLuint texture_id;
    private  bool texture_loaded;
    private bool hovered;
    private int icon_x_offset;
    private int padding_h;
    private int padding_v;
    public int grid_x;
    public int grid_y;

    public int width;
    public int height;

    private int max(int a, int b) {
        return a > b ? a : b;
    }

    public AppEntry(DrawKit.Context ctx, int i, string name, string icon_path, string exec, int padding_h, int padding_v){
        this.name = name;
        this.name_short = name.char_count() > 20 ? name.substring(0, 20) + "..." : name;
        this.icon_path = icon_path;
        this.exec = exec;

        
        width = max(ICON_SIZE, ctx.width_of(name_short, 20)) + 2*ICON_HOVER_PADDING;
        icon_x_offset = (width-ICON_SIZE) / 2;
        height = 15 + ICON_SIZE + 2*ICON_HOVER_PADDING;

        //position
        int row = i / GRID_COLS;
        int col = i % GRID_COLS;
        
        grid_x = PADDING_EDGES + padding_h * col + col * ICON_SIZE - (width/2);
        grid_y = PADDING_EDGES + padding_v * row + row * ICON_SIZE;
    }

    public void mouse_move(double mouse_x, double mouse_y, bool clicked, ref bool redraw){
        int x = grid_x;
        int y = grid_y;
        int w = grid_x + width;
        int h = grid_y + height;
        
        var before = hovered;
        hovered = (mouse_x >= x && mouse_x <= w && mouse_y >= y && mouse_y <= h);
        if(hovered != before) redraw = true;
    }

    public void render(Context ctx){
        if (hovered) {
            ctx.dk_draw_rect_rounded(
                grid_x, 
                grid_y, 
                width,
                height, 
                15.0f,
                { 1.0f, 1.0f, 1.0f, 0.3f });
        }

        // Load texture on demand
        if (!texture_loaded) {
            var tex = ImageUtils.Upload_texture(icon_path, ICON_SIZE);
            texture_id = tex;
            texture_loaded = true;
        }
        
        // Draw icon or placeholder
        if (texture_id > 0) {
            ctx.draw_texture(texture_id, grid_x+icon_x_offset, grid_y+ICON_HOVER_PADDING, ICON_SIZE, ICON_SIZE);
        } else {
            ctx.draw_rect(grid_x+icon_x_offset, grid_y, ICON_SIZE, ICON_SIZE, { 1f, 1f, 1f, 1.0f });
        }

        //label
        ctx.draw_text(name_short, grid_x + width/2, grid_y + ICON_SIZE + 2*ICON_HOVER_PADDING+5, 20);
    }

    private void launch_app(int index) {
        /*  if (index < 0 || index >= apps.length) return;
        
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
        }  */
    }
}

class AppLauncher {

    DrawKit.Context ctx;

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

        ctx = new DrawKit.Context(width, height);
        ctx.set_bg_color(DrawKit.Color(){ r = 0, g =  0, b = 0, a = 0.70f });

        int gaps_h = GRID_COLS + 1;
        int gaps_v = GRID_ROWS + 1;

        //TODO KDE is 2 DPI
        padding_h = (width - GRID_COLS*ICON_SIZE - 2*PADDING_EDGES) / gaps_h;
        padding_v = (height - GRID_ROWS*ICON_SIZE - 2*PADDING_EDGES) / gaps_v;

        var icon_theme = SystemUtils.get_current_theme();
        var icon_paths = IconUtils.find_icon_paths(icon_theme, 96);
        print("using icon theme: %s. Num icons: %i. Displaying: %i\n", icon_theme, icon_paths.size, GRID_COLS*GRID_ROWS);

        var desktop_files = SystemUtils.get_desktop_files(GRID_COLS*GRID_ROWS);
        print("Apps %i\n", desktop_files.length);

        int i = 0;
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
            apps += new AppEntry(ctx, i++, name, icon_path, exec, padding_h, padding_v);
        }
    }

    public void mouse_down() {
        clicked = true;
    }
    public void mouse_up() {
        clicked = false;
    }

    public void mouse_move(double mouse_x, double mouse_y) {
        foreach (var app in apps)
            app.mouse_move(mouse_x, mouse_y, clicked, ref redraw);
    }

    public void render() {
        ctx.begin_frame();
        
        foreach (var app in apps) {
            app.render(ctx);
        }

        ctx.end_frame();
    }
}