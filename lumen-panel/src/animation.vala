using Gee;

private float ease_out_expo(float k) {
    return (k == 1f) ? 1f : (1f - Math.powf(2f, -10f * k));
}

public interface Transition : Object {
    public abstract int id { get; }
    public abstract bool finished { get; }
    public abstract void update(double dt);
}

public class Transition1D : Object, Transition {
    private int _id;
    public int id {get {return _id; }}

    private int* ref_x;
    private int start_x;
    private int end_x;
    private int total_dx;

    private double duration;
    private double t = 0.0;

    private bool _finished = false;
    public bool finished { get { return _finished; } }

    public Transition1D(int id, int* x, int end_x, double duration) {
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
        var e = ease_out_expo(k);

        *ref_x = (int)(start_x + total_dx * e);

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
        int64 current_time_us = get_monotonic_time();
        int64 dt_us = current_time_us - last_time_us;
        last_time_us = current_time_us;
        if (dt_us > 100000) {
            return;
        }

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

        if (transitions.size == 0) has_active = false;
    }
}
