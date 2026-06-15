using Gtk;

// ExpandReveal — the converge effect's lock-surface reveal. Reverses the
// compositor-side converge (wayfire-converge-lock collapsing the desktop to the
// centre vertical seam): the content starts as a zero-width strip at the
// horizontal centre (scale-x = 0) and widens to full (scale-x = 1).
//
// All timing/lifecycle lives in LockReveal; this only maps `progress` to a
// centre-anchored horizontal scale in snapshot().
public class ExpandReveal : LockReveal {

    public ExpandReveal(Gtk.Widget child) {
        base(child);
    }

    public override void snapshot(Gtk.Snapshot s) {
        if (progress >= 0.999) {
            snapshot_child(child, s);
            return;
        }

        float w = (float) get_width();

        // Anchor the horizontal scale at the centre: translate to centre,
        // scale-x, translate back, then draw the child.
        s.save();
        s.translate({ w / 2f, 0f });
        s.scale((float) progress, 1f);
        s.translate({ -w / 2f, 0f });
        snapshot_child(child, s);
        s.restore();
    }
}
