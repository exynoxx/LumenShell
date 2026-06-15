using Gtk;

// LockReveal — abstract base for the lock-surface reveal animations that play
// the second half of a pre-lock transition: the compositor plays its half (the
// desktop collapsing/flipping away over IPC), holds an edge-on/collapsed frame,
// then each lock surface "reveals" out of that held frame so the hand-off feels
// continuous.
//
// Subclasses (ExpandReveal, FlipReveal) only implement snapshot(), reading the
// shared `progress` field (0 = hidden/edge-on, matching the compositor's held
// frame; 1 = fully revealed). The default progress = 1.0 means a surface that
// never calls play() — a late hotplug window, or the no-animation suspend
// path — just appears, with no transform applied.
public abstract class LockReveal : Gtk.Widget {

    protected Gtk.Widget child;
    protected double progress = 1.0;   // 0 = hidden (compositor's held frame), 1 = full
    private int64  start_us = 0;
    private uint   duration_ms = 0;
    private uint   tick_id = 0;

    // Fires once, when the reveal reaches full (progress == 1).
    public signal void finished();

    protected LockReveal(Gtk.Widget child) {
        layout_manager = new Gtk.BinLayout();
        this.child = child;
        child.set_parent(this);
    }

    ~LockReveal() {
        if (tick_id != 0) remove_tick_callback(tick_id);
        if (child != null) child.unparent();
    }

    // Begin the 0 -> 1 reveal. duration should match the compositor transition.
    public void play(uint duration) {
        progress = 0.0;
        start_us = 0;
        duration_ms = duration;
        if (tick_id != 0) remove_tick_callback(tick_id);
        tick_id = add_tick_callback(on_tick);
        queue_draw();
    }

    private bool on_tick(Gtk.Widget widget, Gdk.FrameClock clock) {
        if (start_us == 0) start_us = clock.get_frame_time();

        double t = duration_ms > 0
            ? (clock.get_frame_time() - start_us) / 1000.0 / duration_ms
            : 1.0;

        if (t >= 1.0) {
            progress = 1.0;
            tick_id = 0;
            queue_draw();
            finished();
            return Source.REMOVE;
        }

        progress = ease_out_circ(t);
        queue_draw();
        return Source.CONTINUE;
    }

    // Inverse of a converging circle wipe — mirrors the plugins' "circle" easing.
    protected static double ease_out_circ(double t) {
        return Math.sqrt(1.0 - (t - 1.0) * (t - 1.0));
    }
}
