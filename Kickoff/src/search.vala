using GLib;
using DrawKit;
using Gee;

public class SearchDb {
    public StringBuilder current_search;
    public StringBuilder technical_search;
    public bool active;
    public int size;

    private unowned AppEntry[] all_apps;
    private unowned Context ctx;
    private AppEntry[] grid_apps;

    private const string standard_label = "Search";

    const int KEY_BACKSPACE = 65288;
    const int KEY_CTRL = 65507;


    public SearchDb(Context ctx, AppEntry[] apps, int screen_width, int screen_height) {
        this.ctx = ctx;
        this.all_apps = apps;

        var grid_positions = Utils.Math.Calculate_grid_positions(screen_width, screen_height, PER_PAGE);
        grid_apps = new AppEntry[]{};
        for(int i = 0; i < PER_PAGE; i++){
            grid_apps += new AppEntry(ctx, "..", "..", "..", grid_positions[i].x, grid_positions[i].y);
        }

        current_search = new StringBuilder();
        technical_search = new StringBuilder("*");
        Main.keyboardMngr.on_key = on_key;
    }

    public AppEntry get(int i){
        return grid_apps[i];
    }
    
    public void on_key(uint32 key){
        if(key < 500){
            current_search.append_c((char)key);
            technical_search.append_c((char)key);
            technical_search.append_c('*');
            active = true;
            index();
            Main.queue_redraw();
            return;
        }

        if(key == KEY_BACKSPACE && Main.keyboardMngr.ctrl_down)
        {
            active = false;
            current_search.truncate();
            technical_search.erase(1, technical_search.len - 1);
            Main.queue_redraw();
            return;
        }

        if(key == KEY_BACKSPACE && current_search.len > 0)
        {
            current_search.erase(current_search.len - 1, 1);
            technical_search.erase(technical_search.len - 2, 2);
            active = (current_search.len > 0);
            index();
            Main.queue_redraw();
            return;
        }
    }

    private void index(){

        if(current_search.len == 0) return;
        var q = new PatternSpec(technical_search.str);
        
        size = 0;
        int j = 0;

        //TODO show matched part
        for(int i = 0; i < all_apps.length; i++){
            if(j>= PER_PAGE) break;
            if(q.match_string(all_apps[i].name.ascii_down())){
                grid_apps[j++].populate_from(ctx, all_apps[i]);
                size++;
            }
        }
    }


    public string get_search(){
        if(current_search.len == 0) {
            return standard_label;
        } 
        return current_search.str;
    }
}