using Gtk;

// LockEffect — the pluggable pre-lock transition. Two shapes:
//
//   * Compositor-coordinated (converge): a Wayfire plugin animates the live
//     desktop away over IPC (compositor_ms), holds an edge-on/collapsed frame,
//     then each lock surface reveals out of it (reveal_ms). compositor_ms and
//     reveal_ms are both > 0 and start/stop_compositor drive the plugin.
//   * In-process (flip): no compositor phase (compositor_ms == 0). The manager
//     captures a live screenshot first (needs_snapshot), then the lock surface
//     plays the WHOLE animation itself (reveal_ms > 0) from that screenshot —
//     see FlipReveal. start/stop_compositor are no-ops.
//   * None: lock immediately, surfaces just appear (both durations 0).
//
// Selected once from lockscreen.json (Theme.effect) and owned by LockManager.
//
//   needs_snapshot : the reveal's front face is a live desktop screenshot; the
//                    manager grabs it via wlr-screencopy before locking and
//                    threads it into create_reveal().
//   create_reveal  : the LockReveal wrapper for a surface's content; `snapshot`
//                    is the captured front-face texture (null unless
//                    needs_snapshot, or for a non-captured secondary output).
public interface LockEffect : GLib.Object {

    public abstract uint compositor_ms { get; }
    public abstract uint reveal_ms     { get; }
    public abstract bool needs_snapshot { get; }

    public abstract void start_compositor();
    public abstract void stop_compositor();
    public abstract LockReveal create_reveal(Gtk.Widget content, Gdk.Texture? snapshot);

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
    public bool needs_snapshot { get { return false; } }
    public void start_compositor() {}
    public void stop_compositor() {}
    public LockReveal create_reveal(Gtk.Widget content, Gdk.Texture? snapshot) {
        return new ExpandReveal(content);
    }
}

// Converge: wayfire-converge-lock collapses the desktop to the centre seam; each
// lock surface expands back out of it (ExpandReveal).
public class ConvergeEffect : GLib.Object, LockEffect {
    private uint dur;
    public ConvergeEffect(uint duration_ms) { this.dur = duration_ms; }
    public uint compositor_ms { get { return dur; } }
    public uint reveal_ms     { get { return dur; } }
    public bool needs_snapshot { get { return false; } }
    public void start_compositor() { ConvergeIpc.start(); }
    public void stop_compositor()  { ConvergeIpc.stop(); }
    public LockReveal create_reveal(Gtk.Widget content, Gdk.Texture? snapshot) {
        return new ExpandReveal(content);
    }
}

// Flip: a single in-process 2D-plane rotation. No compositor phase — the manager
// captures the live screen, then the lock surface itself flips that screenshot
// (front face) over 180° to reveal the pre-rendered lock card on the back
// (FlipReveal). One process, one projection, one easing — see FlipReveal.
public class FlipEffect : GLib.Object, LockEffect {
    private bool horizontal;   // true = Y axis, false = X axis
    private uint dur;
    public FlipEffect(bool horizontal, uint duration_ms) {
        this.horizontal = horizontal;
        this.dur = duration_ms;
    }
    public uint compositor_ms { get { return 0; } }     // in-process: no compositor phase
    public uint reveal_ms     { get { return dur; } }
    public bool needs_snapshot { get { return true; } }
    public void start_compositor() {}
    public void stop_compositor()  {}
    public LockReveal create_reveal(Gtk.Widget content, Gdk.Texture? snapshot) {
        return new FlipReveal(content, horizontal, snapshot);
    }
}
