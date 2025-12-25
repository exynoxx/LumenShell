using GLib;
using Gee;

public class SearchDb {
    public StringBuilder current_search;
    public bool active;

    private unowned AppEntry[] apps;
    private const string standard_label = "Search";

    const int KEY_BACKSPACE = 65288;
    const int KEY_CTRL = 65507;

    private int filter_map[PER_PAGE];
    private int size;

    public SearchDb(AppEntry[] apps) {
        this.apps = apps;

        for(int i = 0; i < PER_PAGE; i++) 
            filter_map[i] = i;

        current_search = new StringBuilder();
        Main.keyboardMngr.on_key = on_key;
    }

    public AppEntry get(int i){
        return apps[filter_map[i]];
    }
    
    public void on_key(uint32 key){
        if(key < 500){
            current_search.append_c((char)key);
            active = true;
            index();
            Main.queue_redraw();
            return;
        }

       /*   if(key == KEY_BACKSPACE && key_down_set.contains(KEY_CTRL))
        {
            current_search.truncate();
            Main.queue_redraw();
            return;
        }
  */
        if(key == KEY_BACKSPACE && current_search.len > 0)
        {
            current_search.erase(current_search.len - 1, 1);
            active = (current_search.len > 0)
            index();
            Main.queue_redraw();
            return;
        }
    }

    private void index(){

        if(current_search.len == 0) return;
        var q = current_search.str;
        
        size = 0;
        int j = 0;

        for(int i = 0; i < min(apps.length, PER_PAGE); i++){
            if(apps[i].name.contains(q)){
                filter_map[j++] = i;
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

    private int min(int x, int y){
        return (x<y)?x:y;
    }
}