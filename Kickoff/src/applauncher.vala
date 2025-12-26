using DrawKit;
using WLHooks;
using GLES2;

const int GRID_COLS = 6;
const int GRID_ROWS = 4;
const int PER_PAGE = GRID_COLS*GRID_ROWS;
const int ICON_SIZE = 96;
const int ICON_HOVER_PADDING = 8;
const int THE_MAGIC_CONST = (ICON_SIZE+2*ICON_HOVER_PADDING)/2; //icons are drawn with x coord in center
const int PADDING_EDGES_Y = 130;
const int PADDING_EDGES_X = 200;

public class AppLauncher {
    private int screen_width;
    private int screen_height;
    
    private int screen_center_x;
    private int screen_center_y;

    private float page_x;
    private int active_page;
    private int page_count;

    private float bg_a = 0;
    private float grid_zoom[16];
    private float grid_zoom_factor = 10;
    private float grid_move[16];
    private Transition init_transition;
    private Transition move_transition;

    private DrawKit.Context ctx;
    private AppEntry[] apps;
    private Utils.Span<AppEntry> current_page;
    private Utils.Span<AppEntry> prev_page;

    private Navigation navigation;
    private SearchBar searchbar;
    public SearchDb searchDb;

    public AppLauncher(int width, int height) {
        screen_width = width;
        screen_height = height;

        screen_center_x = screen_width/2;
        screen_center_y = screen_height/2;

        show_overlay();

        ctx = Context.Init_with_groups(width, height, 2);

        var icon_theme = Utils.System.get_current_theme();
        var icon_paths = Utils.Icon.find_icon_paths(icon_theme, 96);
        print("using icon theme: %s. Num icons: %i\n", icon_theme, icon_paths.size);

        var desktop_files = Utils.System.get_desktop_files();
        print("Apps %i\n", desktop_files.length);

        var grid_positions = Utils.Math.Calculate_grid_positions(screen_width, screen_height, desktop_files.length);

        int i = 0;
        foreach (var desktop in desktop_files){
            var entries = Utils.Config.parse(desktop, "Desktop Entry");

            if (entries["Icon"] == null || entries["Exec"] == null || entries["Name"] == null) continue;

            var name = entries["Name"];
            var icon = entries["Icon"];
            var exec = entries["Exec"];

            if(!icon_paths.has_key(icon)){
                continue;
            }

            var icon_path = icon_paths[icon];
            var pos = grid_positions[i++];
            apps += new AppEntry(ctx, name, icon_path, exec, pos.x, pos.y);
        }

        //async
        foreach (var app in apps){
            app.load_texture();
        }

        print("Apps after filter %i\n", apps.length);

        page_count = apps.length/PER_PAGE;
        active_page = 0;
        current_page = new Utils.Span<AppEntry>(apps);
        prev_page = new Utils.Span<AppEntry>(apps);

        print("Pages: %i\n", page_count);

        searchDb = new SearchDb(ctx, apps, screen_width, screen_height);
        navigation = new Navigation(page_count, screen_width, screen_height);
        searchbar = new SearchBar(ctx, screen_center_x);

        init_transition = new Transition1D(1, &grid_zoom_factor, 1, 1.5);
        Main.animations.add(new Transition1D(0, &bg_a, 0.5f, 3));
        Main.animations.add(init_transition);

        move_transition = new TransitionEmpty();
        Utils.Math.translation_matrix_new(grid_move, 0, 0);
    }

    public void show_overlay (){
        WLHooks.init_layer_shell("Kickoff-overlay", screen_width, screen_height, UP | LEFT | RIGHT | DOWN, false);
    }

    public void mouse_move(int mouse_x, int mouse_y) {
        if(searchDb.active){
            for(int i = 0; i < searchDb.size; i++)
            searchDb[i].mouse_move(mouse_x, mouse_y);
            return;
        }

        var absolut_x = mouse_x + active_page*screen_width;
        for(int i = 0; i < PER_PAGE; i++)
            current_page[i].mouse_move(absolut_x, mouse_y);
    }

    public void mouse_down() {
        for(int i = 0; i < PER_PAGE; i++)
            current_page[i].mouse_down();
    }
    public void mouse_up() {
        for(int i = 0; i < PER_PAGE; i++)
            current_page[i].mouse_up();
    }

    public void key_down(uint32 key){
        if(key == 65363){ //r
            if(active_page == page_count-1) return;
            prev_page = current_page;
            active_page++;
            current_page = new Utils.Span<AppEntry>(apps, active_page*PER_PAGE);
        }

        if(key == 65361){ //l
            if(active_page == 0) return;
            prev_page = current_page;
            active_page--;
            current_page = new Utils.Span<AppEntry>(apps, active_page*PER_PAGE);
        }

        if(key == 65361 || key == 65363){
            move_transition = new Transition1D(2, &page_x, -active_page*screen_width, 1.5);
            Main.animations.add(move_transition);
            return;
        }
    }
    
    public void render() {
        ctx.set_bg_color(DrawKit.Color(){ r = 0, g =  0, b = 0, a = bg_a });
        ctx.begin_frame();

        if(!init_transition.finished){
            Utils.Math.centered_zoom_marix(grid_zoom, screen_center_x, screen_center_y, grid_zoom_factor);
            DrawKit.begin_group(2);
            DrawKit.group_matrix(2,grid_zoom);
        }
        
        if(searchDb.active){
            for(int i = 0; i < searchDb.size; i++)
                searchDb[i].render(ctx);
        } else {
            DrawKit.begin_group(1);
            Utils.Math.translation_matrix(grid_move, page_x, 0);
            DrawKit.group_matrix(1, grid_move);

            //main
            for(int i = 0; i < PER_PAGE; i++)
                current_page[i].render(ctx);

            //prev page
            if(!move_transition.finished){
                for(int i = 0; i < PER_PAGE; i++)
                    prev_page[i].render(ctx);
            }
            DrawKit.end_group(1);

            navigation.render(ctx, active_page);
        }

        DrawKit.end_group(2);
        searchbar.render(ctx, searchDb.get_search());

        ctx.end_frame();
    }
}