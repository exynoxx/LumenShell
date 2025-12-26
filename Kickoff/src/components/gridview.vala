using DrawKit;
using WLHooks;
using GLES2;
using Gee;

const int GRID_COLS = 6;
const int GRID_ROWS = 4;
const int PER_PAGE = GRID_COLS*GRID_ROWS;
const int ICON_SIZE = 96;
const int ICON_HOVER_PADDING = 8;
const int THE_MAGIC_CONST = (ICON_SIZE+2*ICON_HOVER_PADDING)/2; //icons are drawn with x coord in center
const int PADDING_EDGES_Y = 130;
const int PADDING_EDGES_X = 200;

public class GridView : IGrid {
    private int screen_width;
    private int screen_height;
    
    private int screen_center_x;
    private int screen_center_y;

    private float page_x;
    public int active_page;
    public int page_count;

    private float bg_a;
    private float grid_zoom[16];
    private float grid_zoom_factor = 10;
    private float grid_move[16];
    private Transition init_transition;
    private Transition move_transition;

    private unowned Context ctx;
    private AppView[] apps;
    private Utils.Span<AppView> current_page;
    private Utils.Span<AppView> prev_page;

    private NavigationBar navigation;

    public GridView(Context ctx, AppEntry[] apps, int width, int height) {
        this.ctx = ctx;
        
        screen_width = width;
        screen_height = height;

        screen_center_x = screen_width/2;
        screen_center_y = screen_height/2;

        var grid_positions = Utils.Math.calculate_grid_positions(screen_width, screen_height, apps.length);
        for(var i = 0; i < apps.length; i++){
            var pos = grid_positions[i];
            var appView = new AppView(pos.x, pos.y);
            appView.set_properties(ctx, apps[i]);
            this.apps += appView;
        }

        page_count = apps.length/PER_PAGE;
        active_page = 0;
        current_page = new Utils.Span<AppView>(this.apps);
        prev_page = new Utils.Span<AppView>(this.apps);

        init_transition = new Transition1D(1, &grid_zoom_factor, 1, 1.5);
        Main.animations.add(new Transition1D(0, &bg_a, 0.5f, 3));
        Main.animations.add(init_transition);

        move_transition = new TransitionEmpty();
        Utils.Math.translation_matrix_new(grid_move, 0, 0);

        navigation = new NavigationBar(ctx, screen_width, screen_height, page_count);
    }

    public void mouse_move(int mouse_x, int mouse_y) {
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
            navigation.active_page = active_page;
            current_page = new Utils.Span<AppView>(apps, active_page*PER_PAGE);
        }

        if(key == 65361){ //l
            if(active_page == 0) return;
            prev_page = current_page;
            active_page--;
            navigation.active_page = active_page;
            current_page = new Utils.Span<AppView>(apps, active_page*PER_PAGE);
        }

        if(key == 65361 || key == 65363){
            move_transition = new Transition1D(2, &page_x, -active_page*screen_width, 1.5);
            Main.animations.add(move_transition);
            return;
        }
    }
    
    public void render() {
        ctx.set_bg_color(DrawKit.Color(){ r = 0, g =  0, b = 0, a = bg_a });

        if(!init_transition.finished){
            Utils.Math.centered_zoom_marix(grid_zoom, screen_center_x, screen_center_y, grid_zoom_factor);
            DrawKit.begin_group(2);
            DrawKit.group_matrix(2,grid_zoom);
        }
        
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
        DrawKit.end_group(2);

        navigation.render();
    }
}