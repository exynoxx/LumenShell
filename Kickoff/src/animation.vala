using Gee;

public interface Transition : Object {
    public abstract int id { get; }
    public abstract bool finished { get; }
    public abstract void update(double dt);

    public float easeOutExpo(float k){
        return (k == 1f) ? 1f : (1f - Math.powf(2f, -10f * k));
    }
}

public class Transition1D : Object, Transition {
    private int _id;
    public int id {get {return _id; }}

    private float* ref_x;
    private float start_x;
    private float end_x;
    private float total_dx;

    private double duration;
    private double t = 0.0;
    private float last_progress = 0f;

    private bool _finished = false;
    public bool finished { get { return _finished; } }

    public Transition1D(int id, float* x, float end_x, double duration) {
        _id = id;
        ref_x = x;
        start_x = *x;
        total_dx = end_x - *x;
        this.end_x = end_x;
        this.duration = duration;
    }

    public void update(double dt) {
        if (finished) return;

        t += dt;
        var k = float.min((float)(t / duration), 1.0f);
        var e = easeOutExpo(k);

        var ex = start_x + total_dx * e;

        // apply
        *ref_x += ex-(*ref_x);

        if (k >= 1.0) {
            *ref_x = end_x;
            _finished = true;
        }
    }
}

public class AnimationManager : Object {
    private HashMap<int,Transition> transitions = new HashMap<int,Transition>();
    public bool has_active = false;

    private int64 last_time_us;

    public AnimationManager(){
        last_time_us = get_monotonic_time();
    }

    public void add(Transition t) {
        transitions[t.id] = t;
        has_active = true;
    }

    public void update() {
        
        // Get current time in microseconds
        int64 current_time_us = get_monotonic_time();
        //print("update %lld\n", current_time_us-last_time_us);
        int64 dt_us = current_time_us-last_time_us;
        last_time_us = current_time_us;
        if(dt_us > 100000){
            //wait for framerate to warmup
            return;
        }

        // Calculate delta time in seconds (convert from microseconds)
        double dt = dt_us / 1000000.0;
        
        foreach (var t in transitions.values) {
            t.update(dt);
        }

        var iter = transitions.map_iterator();
        while (iter.next()) {
            if (iter.get_value().finished) {
                iter.unset();
            }
        }
        
        if(transitions.size == 0) has_active = false;
    }
}


/*  public class MoveTransition : Object, Transition {

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
}  */