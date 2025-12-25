using GLib;

public class SearchDb {

    const int64 INITIAL_INTERVAL_MS = 150;
    const int64 REPEAT_INTERVAL_MS = 50;
    const int BACKSPACE_KEYCODE = 8;

    int64 last_time = 0; // in milliseconds

    private Gee.HashSet<char> key_down_set;
    private bool initial_delayed = false;

    private string[] strings;
    private const string standard_label = "Search";
    
    public StringBuilder current_search;
    public bool key_is_down = false;

    public SearchDb(AppEntry[] apps) {
        foreach (var app in apps){
            strings += app.name;
        }

        current_search = new StringBuilder();
        key_down_set = new Gee.HashSet<char>();
    }

    public void key_down(char key){
        initial_delayed = false;

        key_down_set.add(key);
        key_is_down = true;

        on_key(key);
        last_time = get_monotonic_time();
    }

    public void key_up(char key){
        key_down_set.remove(key);

        if(key_down_set.size == 0) {
            key_is_down = false;
            initial_delayed = false;
        }
        last_time = get_monotonic_time();
    }

    public void main_loop(){
        var delay = (initial_delayed) ? REPEAT_INTERVAL_MS : INITIAL_INTERVAL_MS;
        if (get_elapsed_ms() < delay) {
            Main.queue_redraw(); //keep compositor from sleeping??
            return; // too early, skip
        }
        initial_delayed = true;

        foreach(var key in key_down_set){
            on_key(key);
        }
        last_time = get_monotonic_time();
    }

    private void on_key(char key){
        if(key == 8 && current_search.len > 0) //backspace
        {
            current_search.erase(current_search.len - 1, 1);
            Main.queue_redraw();
            return;
        }

        if(key != 8){
            current_search.append_c(key);
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

    private int64 get_elapsed_ms(){
        int64 now = get_monotonic_time();
        var elapsed = now - last_time;
        return elapsed / 1000; // microseconds → ms;
    }
}