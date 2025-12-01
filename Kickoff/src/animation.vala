public interface Transition : Object {
    public abstract bool finished { get; }
    public abstract void update(double dt);
}

public class MoveTransition : Object, Transition {
    public int x;
    public int y;
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

    public MoveTransition(int start_x, int start_y,
                          int end_x,   int end_y,
                          double duration) {
        this.x = this.start_x = start_x;
        this.y = this.start_y = start_y;
        this.end_x = end_x;
        this.end_y = end_y;
        this.duration = duration;
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
        x = start_x + (int)((end_x - start_x) * e);
        y = start_y + (int)((end_y - start_y) * e);

        if (k >= 1.0)
            _finished = true;
    }
}

public class AnimationManager : Object {
    private Gee.ArrayList<Transition> transitions = new Gee.ArrayList<Transition>();

    public void add(Transition t) {
        transitions.add(t);
    }

    public void update(double dt) {
        var to_remove = new Gee.ArrayList<Transition>();
        
        foreach (var t in transitions) {
            t.update(dt);
            if (t.finished)
                to_remove.add(t);
        }
        
        // Remove finished transitions
        foreach (var t in to_remove)
            transitions.remove(t);
    }
}

/*  double last_time = now();

void render_frame() {
    double current = now();
    double dt = current - last_time;
    last_time = current;

    ctx.begin_frame();

    animation_manager.update(dt);
    animation_manager.draw();

    ctx.end_frame();
}

animation_manager.add(
    new MoveTransition(0, 0, 400, 0, 0.5)
);

*/