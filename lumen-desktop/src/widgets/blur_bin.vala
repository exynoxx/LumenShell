// Single-child container that applies a GSK Gaussian blur to the rendered
// subtree. Implemented via `Gtk.Snapshot.push_blur` so the work happens on
// the GPU inside the GSK render pass — no offscreen Cairo, no widget-tree
// duplication. Radius is a runtime-settable property animated by the owner
// (see DesktopWindow.animate_blur_to).
public class BlurBin : Gtk.Widget {

    // Below this we skip push_blur entirely: at sub-pixel radii the effect
    // is invisible but still pays the offscreen-render cost.
    private const double EPSILON = 0.5;

    private double _radius = 0.0;
    public double radius {
        get { return _radius; }
        set {
            if (_radius == value) return;
            _radius = value;
            queue_draw();
        }
    }

    private Gtk.Widget? child_widget;

    construct {
        set_hexpand(true);
        set_vexpand(true);
    }

    public void set_child(Gtk.Widget? c) {
        if (child_widget == c) return;
        if (child_widget != null) child_widget.unparent();
        child_widget = c;
        if (child_widget != null) child_widget.set_parent(this);
        queue_resize();
    }

    public override void dispose() {
        if (child_widget != null) {
            child_widget.unparent();
            child_widget = null;
        }
        base.dispose();
    }

    public override void measure(Gtk.Orientation orientation, int for_size,
                                 out int minimum, out int natural,
                                 out int minimum_baseline, out int natural_baseline) {
        if (child_widget != null) {
            child_widget.measure(orientation, for_size,
                out minimum, out natural,
                out minimum_baseline, out natural_baseline);
        } else {
            minimum = 0;
            natural = 0;
            minimum_baseline = -1;
            natural_baseline = -1;
        }
    }

    public override void size_allocate(int width, int height, int baseline) {
        if (child_widget != null) {
            child_widget.allocate(width, height, baseline, null);
        }
    }

    public override void snapshot(Gtk.Snapshot s) {
        if (child_widget == null) return;
        if (_radius > EPSILON) {
            s.push_blur(_radius);
            snapshot_child(child_widget, s);
            s.pop();
        } else {
            snapshot_child(child_widget, s);
        }
    }
}
