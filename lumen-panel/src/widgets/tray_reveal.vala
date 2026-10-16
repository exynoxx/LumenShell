using Gtk;

// Single-child clip-reveal: the child is always allocated its full natural size
// at a fixed corner, and one eased `fraction` drives the visible bloom.
public class TrayReveal : Gtk.Widget {

    Gtk.Widget? _child = null;
    double _fraction = 0.0;   // 0 = collapsed, 1 = fully expanded
    bool   anchor_top;        // pin top-right (top panel) vs bottom-right

    uint  tick_id = 0;
    int64 anim_start_us = 0;
    double anim_from = 0.0;
    double anim_to   = 0.0;
    bool  _target = false;    // desired expanded state

    const int64 DURATION_US = 260000;

    public signal void animation_done ();
    public signal void fraction_changed (double fraction);

    public double fraction { get { return _fraction; } }

    public TrayReveal (bool anchor_top) {
        this.anchor_top = anchor_top;
        overflow = Gtk.Overflow.HIDDEN;
        halign = Gtk.Align.END;
        valign = anchor_top ? Gtk.Align.START : Gtk.Align.END;
    }

    public Gtk.Widget? child {
        get { return _child; }
        set {
            if (_child != null) _child.unparent ();
            _child = value;
            if (_child != null) _child.set_parent (this);
            queue_resize ();
        }
    }

    public bool revealed  { get { return _target; } }
    public bool animating { get { return tick_id != 0; } }

    public void set_reveal (bool reveal) {
        if (reveal == _target && tick_id == 0) return;
        _target = reveal;
        anim_from = _fraction;
        anim_to   = reveal ? 1.0 : 0.0;
        anim_start_us = 0;
        if (tick_id == 0) tick_id = add_tick_callback (on_tick);
        // Grow the surface to full size in ONE step on expand; on collapse it shrinks
        // only once the animation settles (on_tick).
        queue_resize ();
    }

    bool on_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        if (anim_start_us == 0) anim_start_us = clock.get_frame_time ();
        double t = (double) (clock.get_frame_time () - anim_start_us) / DURATION_US;
        if (t >= 1.0) {
            set_fraction (anim_to);
            tick_id = 0;
            // tick_id is 0 now, so on collapse surface_full flips false: shrink once.
            queue_resize ();
            animation_done ();
            return GLib.Source.REMOVE;
        }
        // ease-out cubic: fast start, gentle settle.
        double inv = 1.0 - t;
        double eased = 1.0 - inv * inv * inv;
        set_fraction (anim_from + (anim_to - anim_from) * eased);
        return GLib.Source.CONTINUE;
    }

    void set_fraction (double f) {
        _fraction = f.clamp (0.0, 1.0);
        fraction_changed (_fraction);
        // Per-frame changes are draw-only; a resize would reconfigure the layer surface.
        queue_draw ();
    }

    public override void measure (Gtk.Orientation orientation, int for_size,
                                  out int minimum, out int natural,
                                  out int minimum_baseline, out int natural_baseline) {
        minimum = 0;
        natural = 0;
        minimum_baseline = -1;
        natural_baseline = -1;
        if (_child == null || !_child.visible) return;

        int cmin, cnat, ib, nb;
        _child.measure (orientation, -1, out cmin, out cnat, out ib, out nb);
        // Full extent for the whole open cycle, so the surface resizes only twice.
        // Must be the MINIMUM: GTK only grows a layer-shell surface to the content's minimum.
        bool surface_full = _target || tick_id != 0;
        minimum = surface_full ? cnat : 0;
        natural = minimum;
    }

    public override void size_allocate (int width, int height, int baseline) {
        if (_child == null) return;

        int cw_min, cw_nat, ch_min, ch_nat, ib, nb;
        _child.measure (Gtk.Orientation.HORIZONTAL, -1, out cw_min, out cw_nat, out ib, out nb);
        _child.measure (Gtk.Orientation.VERTICAL,   -1, out ch_min, out ch_nat, out ib, out nb);

        // Never re-laid-out, so it can't judder; snapshot() does the visible reveal.
        int x = width - cw_nat;
        int y = anchor_top ? 0 : height - ch_nat;
        var t = new Gsk.Transform ().translate ({ (float) x, (float) y });
        _child.allocate (cw_nat, ch_nat, baseline, t);
    }

    // Scale-from-corner bloom with a faster opacity fade; the child scales as one
    // unit, so there is no reflow.
    public override void snapshot (Gtk.Snapshot s) {
        if (_child == null) return;
        int w = get_width ();
        int h = get_height ();
        if (w <= 0 || h <= 0) return;
        double scale = _fraction;
        if (scale <= 0.0) return;

        // The fixed corner the bloom grows out of, in widget-local coords.
        float pivot_x = (float) w;                        // right edge
        float pivot_y = anchor_top ? 0.0f : (float) h;    // top- vs bottom-right
        double alpha = (_fraction * 1.6).clamp (0.0, 1.0);

        s.save ();
        s.translate ({ pivot_x, pivot_y });
        s.scale ((float) scale, (float) scale);
        s.translate ({ -pivot_x, -pivot_y });
        s.push_opacity (alpha);
        snapshot_child (_child, s);
        s.pop ();
        s.restore ();
    }

    public override void dispose () {
        if (_child != null) {
            _child.unparent ();
            _child = null;
        }
        base.dispose ();
    }
}
