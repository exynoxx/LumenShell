using GLib;
using Gee;

public delegate void OnKeyCallback(uint32 key);

public class KeyboardManager {

    const int64 INITIAL_INTERVAL_MS = 200;
    const int64 REPEAT_INTERVAL_MS = 50;

    const int KEY_BACKSPACE = 65288;
    const int KEY_CTRL = 65507;

    int64 last_time = 0; // in milliseconds

    private HashSet<uint32> key_down_set;
    private bool initial_delayed = false;

    public bool key_is_down = false;
    public bool ctrl_down = false;

    public OnKeyCallback on_key_down = () => 1+1;
    public OnKeyCallback on_key_up = () => 1+1;

    public KeyboardManager() {
        key_down_set = new HashSet<uint32>();
    }

    public void key_down(uint32 key){
        initial_delayed = false;

        key_down_set.add(key);
        key_is_down = true;

        if(key == KEY_CTRL) ctrl_down = true;

        on_key_down(key);
        last_time = get_monotonic_time();
    }

    public void key_up(uint32 key){
        key_down_set.remove(key);

        if(key == KEY_CTRL) ctrl_down = false;

        if(key_down_set.size == 0) {
            key_is_down = false;
            initial_delayed = false;
        }
        last_time = get_monotonic_time();
        on_key_up(key);
    }
    
    public void main_loop(){
        var delay = (initial_delayed) ? REPEAT_INTERVAL_MS : INITIAL_INTERVAL_MS;
        if (get_elapsed_ms() < delay) {
            Main.queue_redraw(); //keep compositor from sleeping??
            return; // too early, skip
        }
        initial_delayed = true;

        foreach(var key in key_down_set){
            on_key_down(key);
        }
        last_time = get_monotonic_time();
    }

    private int64 get_elapsed_ms(){
        int64 now = get_monotonic_time();
        var elapsed = now - last_time;
        return elapsed / 1000; // microseconds → ms;
    }
}