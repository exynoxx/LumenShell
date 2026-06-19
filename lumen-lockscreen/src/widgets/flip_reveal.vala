using Gtk;

// FlipReveal — the in-process "card flip" lock reveal. The entire animation runs
// inside this ONE lock surface: a single 2D plane rotates 180° about the chosen
// axis. There is no compositor coordination.
//
//   FRONT face (0°–90°)  = a live screenshot of the desktop captured (via
//                          wlr-screencopy) just before locking. Because the lock
//                          surface's very first committed frame is that
//                          screenshot at 0° (flat, full-screen), it is
//                          pixel-identical to what was already on screen, so the
//                          hand-off across ext-session-lock's blank is invisible.
//   BACK face (90°–180°) = the lock card (avatar + password over the blurred
//                          backdrop), pre-rendered so it is already there when
//                          the plane turns over to reveal it.
//
// 90° is edge-on (zero width, invisible) — the instant the visible face swaps.
// Both faces share one projection, pivot and easing, so the motion reads as a
// single continuous plane turning over (unlike the old two-process flip, where a
// Wayfire plugin foreshortened the desktop with an orthographic squash and the
// lock surface rotated back out of the held frame with a different — perspective
// — projection, so the two halves never matched).
//
// `front` may be null (capture failed, or a secondary output that was not
// captured): the reveal then has no front face and the manager presents the card
// without playing it (progress stays at its default 1.0).
public class FlipReveal : LockReveal {

    private bool horizontal;          // true = Y axis (about vertical), false = X
    private Gtk.Picture? front = null;

    public FlipReveal(Gtk.Widget child, bool horizontal, Gdk.Texture? front_tex) {
        base(child);
        this.horizontal = horizontal;
        if (front_tex != null) {
            front = new Gtk.Picture() {
                content_fit = Gtk.ContentFit.COVER,
                hexpand     = true,
                vexpand     = true,
                can_target  = false,   // never intercept clicks meant for the card
                can_focus   = false,
            };
            front.set_paintable(front_tex);
            front.set_parent(this);    // BinLayout sizes it to fill, like `child`
        }
    }

    ~FlipReveal() {
        if (front != null) front.unparent();
    }

    public override void snapshot(Gtk.Snapshot s) {
        // Fully revealed: just the card, untransformed (also the input-correct
        // resting state — see LockReveal).
        if (progress >= 0.999) {
            snapshot_child(child, s);
            return;
        }

        float w = (float) get_width();
        float h = (float) get_height();

        // One plane turning 0° (front flat = the live screenshot) -> 180° (back
        // flat = the lock card).
        float angle = (float) (progress * 180.0);

        // Gentle perspective tied to surface size for consistent foreshortening.
        float depth = (float) (2.0 * Math.fmax(w, h));

        Graphene.Vec3 axis = {};
        if (horizontal)
            axis.init(0f, 1f, 0f);   // Y axis
        else
            axis.init(1f, 0f, 0f);   // X axis

        if (angle <= 90f) {
            // Front half: show the live screenshot foreshortening toward edge-on.
            if (front == null) return;
            var t = new Gsk.Transform();
            t = t.translate({ w / 2f, h / 2f });
            t = t.perspective(depth);
            t = t.rotate_3d(angle, axis);
            t = t.translate({ -w / 2f, -h / 2f });
            s.save();
            s.transform(t);
            snapshot_child(front, s);
            s.restore();
        } else {
            // Back half: the lock card. Pre-rotate it 180° about the same axis so
            // that at the plane's 180° it lands upright and un-mirrored (two 180°
            // turns about one axis cancel).
            var t = new Gsk.Transform();
            t = t.translate({ w / 2f, h / 2f });
            t = t.perspective(depth);
            t = t.rotate_3d(angle, axis);
            t = t.rotate_3d(180f, axis);
            t = t.translate({ -w / 2f, -h / 2f });
            s.save();
            s.transform(t);
            snapshot_child(child, s);
            s.restore();
        }
    }
}
