using Gtk;

// LockEffect — the pluggable pre-lock transition. Generalises what used to be
// the hard-wired converge: a compositor-side phase (a Wayfire plugin animating
// the live desktop away over IPC) followed by a GTK-side reveal (each lock
// surface animating out of the held frame). Selected once from lockscreen.json
// (Theme.effect) and owned by LockManager.
//
//   compositor_ms : how long to wait after start_compositor() before requesting
//                   the lock (must match the plugin's animation duration). 0
//                   means there is no compositor phase — lock immediately.
//   reveal_ms     : how long the lock-surface reveal runs. 0 means no reveal —
//                   surfaces just appear.
//   start/stop_compositor : drive the Wayfire plugin (no-op when not under
//                   Wayfire or the plugin isn't loaded; the lock still proceeds).
//   create_reveal : the LockReveal wrapper for a surface's content.
//
// An effect either has BOTH phases (compositor_ms > 0 && reveal_ms > 0) or
// NEITHER (none). LockManager relies on that to guarantee stop_compositor() is
// always reached after a start_compositor().
public interface LockEffect : GLib.Object {

    public abstract uint compositor_ms { get; }
    public abstract uint reveal_ms     { get; }

    public abstract void start_compositor();
    public abstract void stop_compositor();
    public abstract LockReveal create_reveal(Gtk.Widget content);

    // Build the configured effect. Unknown names fall back to "converge".
    public static LockEffect from_config() {
        switch (Theme.effect) {
            case "none":
                return new NoneEffect();
            case "flip":
                return new FlipEffect(Theme.flip_axis != "x", (uint) Theme.effect_duration_ms);
            case "converge":
            default:
                return new ConvergeEffect((uint) Theme.effect_duration_ms);
        }
    }
}

// No transition: lock immediately, surfaces appear with no animation. The
// ExpandReveal is left at its default (progress = 1, drawn straight through)
// and never played.
public class NoneEffect : GLib.Object, LockEffect {
    public uint compositor_ms { get { return 0; } }
    public uint reveal_ms     { get { return 0; } }
    public void start_compositor() {}
    public void stop_compositor() {}
    public LockReveal create_reveal(Gtk.Widget content) { return new ExpandReveal(content); }
}

// Converge: wayfire-converge-lock collapses the desktop to the centre seam; each
// lock surface expands back out of it (ExpandReveal).
public class ConvergeEffect : GLib.Object, LockEffect {
    private uint dur;
    public ConvergeEffect(uint duration_ms) { this.dur = duration_ms; }
    public uint compositor_ms { get { return dur; } }
    public uint reveal_ms     { get { return dur; } }
    public void start_compositor() { ConvergeIpc.start(); }
    public void stop_compositor()  { ConvergeIpc.stop(); }
    public LockReveal create_reveal(Gtk.Widget content) { return new ExpandReveal(content); }
}

// Flip: wayfire-flip-lock rotates the desktop edge-on about the Y or X axis; each
// lock surface rotates back out of the edge-on frame (FlipReveal), so the lock
// reads as the "back side" of the flip.
public class FlipEffect : GLib.Object, LockEffect {
    private bool horizontal;   // true = Y axis, false = X axis
    private uint dur;
    public FlipEffect(bool horizontal, uint duration_ms) {
        this.horizontal = horizontal;
        this.dur = duration_ms;
    }
    public uint compositor_ms { get { return dur; } }
    public uint reveal_ms     { get { return dur; } }
    public void start_compositor() { FlipIpc.start(horizontal ? "y" : "x"); }
    public void stop_compositor()  { FlipIpc.stop(); }
    public LockReveal create_reveal(Gtk.Widget content) {
        return new FlipReveal(content, horizontal);
    }
}
