public interface Transition : Object {
    public abstract bool finished { get; }
    public abstract void update(double dt);
}

public class MoveTransition : Object, Transition {

    private int *ref_x;
    private int *ref_y;

    public int start_x;
    public int start_y;
    public int end_x;
    public int end_y;
    public double duration;
    private double t = 0.0;

    private bool _finished = false;
    public bool finished { 
        get { return _finished; }
    }

    public MoveTransition(int* x, int* y, int end_x, int end_y, double duration) {
        ref_x = x;
        ref_y = y;

        this.start_x = *x;
        this.start_y = *y;
        this.end_x = end_x;
        this.end_y = end_y;
        this.duration = duration;
        // Don't initialize t here - it should start at 0.0
    }

    public void update(double dt) {
        if (finished) return;

        t += dt;
        double k = double.min(t / duration, 1.0);
        
        // easing: easeOutExpo
        double e = 1.0;
        if (k != 1.0)
            e = 1.0 - Math.pow(2.0, -10.0 * k);

        // compute eased float values and convert to int
        *ref_x = start_x + (int)((end_x - start_x) * e);
        *ref_y = start_y + (int)((end_y - start_y) * e);

        if (k >= 1.0)
            _finished = true;
    }
}

public class AnimationManager : Object {
    private Gee.ArrayList<Transition> transitions = new Gee.ArrayList<Transition>();
    public bool has_active = true;

    private int64 last_time_us;

    public AnimationManager(){
        last_time_us = get_monotonic_time();
    }

    public void add(Transition t) {
        transitions.add(t);
        has_active = true;
    }

    public void update() {
        var to_remove = new Gee.ArrayList<Transition>();

        // Get current time in microseconds
        int64 current_time_us = get_monotonic_time();
        
        // Calculate delta time in seconds (convert from microseconds)
        double dt = (current_time_us - last_time_us) / 1000000.0;
        
        last_time_us = current_time_us;

        foreach (var t in transitions) {
            t.update(dt);
            if (t.finished)
                to_remove.add(t);
        }
        
        // Remove finished transitions
        foreach (var t in to_remove)
            transitions.remove(t);

        if(transitions.size == 0) has_active = false;

    }
}