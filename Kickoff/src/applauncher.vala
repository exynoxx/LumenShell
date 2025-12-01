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
        padding_h = (width - GRID_COLS*ICON_SIZE) / gaps_h;
        padding_v = (height - GRID_ROWS*ICON_SIZE) / gaps_v;

        var icon_theme = SystemUtils.get_current_theme();
        var icon_paths = IconUtils.find_icon_paths(icon_theme, 96);
        print("using icon theme: %s. Num icons: %i. Displaying: %i\n", icon_theme, icon_paths.size, GRID_COLS*GRID_ROWS);

        var desktop_files = SystemUtils.get_desktop_files(GRID_COLS*GRID_ROWS);
        print("Apps %i\n", desktop_files.length);

        int i = 0;
        foreach (var desktop in desktop_files){
            var entries = ConfigUtils.parse(desktop, "Desktop Entry");
            var icon = entries["Icon"];
            var exec = entries["Exec"]
                .replace("%f", "")
                .replace("%F", "")
                .replace("%u", "")
                .replace("%U", "")
                .replace("%i", "")
                .replace("%c", "")
                .strip();
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
        foreach (var app in apps)
            app.mouse_down(ref redraw);
    }
    public void mouse_up() {
        foreach (var app in apps)
            app.mouse_up(ref redraw);
    }

    public void mouse_move(double mouse_x, double mouse_y) {
        foreach (var app in apps)
            app.mouse_move(mouse_x, mouse_y, ref redraw);
    }

    public void render() {
        ctx.begin_frame();
        
        foreach (var app in apps) {
            app.render(ctx);
        }

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
}