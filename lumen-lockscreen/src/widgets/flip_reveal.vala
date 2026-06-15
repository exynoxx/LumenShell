using Gtk;

// FlipReveal — the flip effect's lock-surface reveal. The lock content is the
// "back side" of the flip: the compositor (wayfire-flip-lock) rotates the frozen
// desktop edge-on about the chosen axis and holds; this rotates the lock content
// back from edge-on (90°) to flat (0°) about the SAME axis, so the screen reads
// as a single plane turning over to reveal the lock on its reverse face.
//
// Unlike ExpandReveal's flat scale, this is a real 3D rotation with perspective
// (GSK perspective + rotate_3d), pivoted at the surface centre. The axis is set
// by LockManager from lockscreen.json and must match the compositor's run axis.
public class FlipReveal : LockReveal {

    private bool horizontal;   // true = Y axis (rotate about vertical), false = X axis

    public FlipReveal(Gtk.Widget child, bool horizontal) {
        base(child);
        this.horizontal = horizontal;
    }

    public override void snapshot(Gtk.Snapshot s) {
        if (progress >= 0.999) {
            snapshot_child(child, s);
            return;
        }

        float w = (float) get_width();
        float h = (float) get_height();

        // 90° (edge-on, matching the compositor's held frame) -> 0° (flat).
        float angle = (float) ((1.0 - progress) * 90.0);

        // Larger depth = gentler perspective; tie it to the surface size so the
        // foreshortening looks consistent across monitors.
        float depth = (float) (2.0 * Math.fmax(w, h));

        Graphene.Vec3 axis = {};
        if (horizontal)
            axis.init(0f, 1f, 0f);   // Y axis
        else
            axis.init(1f, 0f, 0f);   // X axis

        var t = new Gsk.Transform();
        t = t.translate({ w / 2f, h / 2f });
        t = t.perspective(depth);
        t = t.rotate_3d(angle, axis);
        t = t.translate({ -w / 2f, -h / 2f });

        s.save();
        s.transform(t);
        snapshot_child(child, s);
        s.restore();
    }
}
