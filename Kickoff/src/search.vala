using GLib;
using Gee;

public class SearchDb {
    public StringBuilder current_search;
    
    private string[] strings;
    private const string standard_label = "Search";

    const int KEY_BACKSPACE = 65288;
    const int KEY_CTRL = 65507;

    public SearchDb(AppEntry[] apps) {
        foreach (var app in apps){
            strings += app.name;
        }

        current_search = new StringBuilder();
        Main.keyboardMngr.on_key = on_key;
    }
    
    public void on_key(uint32 key){
        if(key < 500){
            current_search.append_c((char)key);
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
            Main.queue_redraw();
            return;
        }
    }

    public string get_search(){
        if(current_search.len == 0) {
            return standard_label;
        } 
        return current_search.str;
    }
}