using GLib;
using DrawKit;
using Gee;

public class SearchDb {
    public StringBuilder current_search;
    public StringBuilder technical_search;
    public bool active;
    public int size;

    private unowned AppEntry[] all_apps;
    public Utils.AliasArray<AppEntry> filtered;

    private const string standard_label = "Search";

    const int KEY_BACKSPACE = 65288;
    const int KEY_CTRL = 65507;

    public SearchDb(AppEntry[] apps, int screen_width, int screen_height) {
        this.all_apps = apps;

        filtered = new Utils.AliasArray<AppEntry>(apps, PER_PAGE);

        current_search = new StringBuilder();
        technical_search = new StringBuilder("*");
    }
    
    public void on_key(uint32 key){
        if(key < 500){
            var c = (char) key;
            current_search.append_c(c);
            technical_search.append_c(c.tolower());
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

    //TODO show matched part
    private void index(){
        if(current_search.len == 0) return;

        var search_lc = current_search.str.ascii_down();
        var included = new bool[all_apps.length];

        size = 0;
        for(int i = 0; i < all_apps.length; i++){
            if(size>= PER_PAGE) break;
            if(all_apps[i].name.has_prefix(search_lc))
            {
                included[i] = true; 
                filtered.alias_index(size++,i);
            }
        }

        var q = new PatternSpec(technical_search.str);
        for(int i = 0; i < all_apps.length; i++){
            if(size>= PER_PAGE) break;

            if(!included[i] && q.match_string(all_apps[i].name))
                filtered.alias_index(size++,i);
        }
    }

    public string get_search(){
        if(current_search.len == 0) {
            return standard_label;
        } 
        return current_search.str;
    }
}