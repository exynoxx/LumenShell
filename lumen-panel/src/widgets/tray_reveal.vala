using Gtk;

// A single-child clip-reveal container, the smooth replacement for the two
// nested Gtk.Revealers the tray used to expand with.
//
// The old approach nested a width-sliding revealer inside a height-sliding one.
// Each ran on its own animation clock (so they desynced), and Gtk.Revealer's
// SLIDE transitions re-measure and translate the child every frame — which made
// the ControlCenter reflow mid-animation. The result was diagonal, juddery
// growth.
//
// This widget instead allocates the child its FULL natural size every frame,
// anchored to a fixed corner, and animates only the size IT reports upward to
// its parent. The parent (and the layer surface) grow/shrink smoothly while the
// child stays put and is simply clipped (overflow HIDDEN). One eased scalar
// `fraction` drives width and height together, so there is no two-timer desync
// and no reflow. The animation is hand-driven by a single tick callback, the
// same pattern panel_window uses for its auto-hide slide.
public class TrayReveal : Gtk.Widget {

    Gtk.Widget? _child = null;
    double _fraction = 0.0;   // 0 = collapsed, 1 = fully expanded
    bool   anchor_top;        // pin top-right (top panel) vs bottom-right

    uint  tick_id = 0;
    int64 anim_start_us = 0;
    double anim_from = 0.0;
    double anim_to   = 0.0;
    bool  _target = false;    // desired expanded state

    const int64 DURATION_US = 260000;   // 260 ms

    // Fires once when an expand or collapse animation settles.
    public signal void animation_done ();
    // Fires every frame with the eased 0..1 progress, so the compact icon row can
    // crossfade in step with the reveal.
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
        // Grow the surface to its full expanded size in ONE step (expand) — the
        // reveal itself is then a pure clip animation in snapshot(), with no
        // per-frame layer-shell surface resize. On collapse this is a size no-op
        // (surface_full stays true while tick_id != 0); the shrink happens once
        // the animation settles, in on_tick's terminal branch below.
        queue_resize ();
    }

    bool on_tick (Gtk.Widget w, Gdk.FrameClock clock) {
        if (anim_start_us == 0) anim_start_us = clock.get_frame_time ();
        double t = (double) (clock.get_frame_time () - anim_start_us) / DURATION_US;
        if (t >= 1.0) {
            set_fraction (anim_to);
            tick_id = 0;
            // tick_id is now 0, so on a collapse surface_full flips to false:
            // resize once to shrink the surface back to the icon-row floor.
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
        // Only the visible clip changes per frame, not the surface size — a
        // queue_draw (GPU compositing) instead of queue_resize (full relayout +
        // Wayland surface reconfigure). This is what makes the reveal smooth
        // without depending on CPU clock.
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
        // Size the surface to the FULL expanded extent for the whole open cycle
        // (while expanded OR animating in either direction), so the layer-shell
        // surface resizes only twice per cycle — once to grow on expand, once to
        // shrink when collapse settles — instead of every animation frame. The
        // visible reveal is a clip animated in snapshot() (driven by queue_draw),
        // not by the size reported here.
        //
        // It must be the MINIMUM, not just the natural: the panel is a layer-shell
        // surface and GTK only grows the surface to satisfy the content's MINIMUM
        // size — a natural-only request leaves the surface collapsed and clips the
        // Control Center to a sliver.
        bool surface_full = _target || tick_id != 0;
        minimum = surface_full ? cnat : 0;
        natural = minimum;
    }

    public override void size_allocate (int width, int height, int baseline) {
        if (_child == null) return;

        int cw_min, cw_nat, ch_min, ch_nat, ib, nb;
        _child.measure (Gtk.Orientation.HORIZONTAL, -1, out cw_min, out cw_nat, out ib, out nb);
        _child.measure (Gtk.Orientation.VERTICAL,   -1, out ch_min, out ch_nat, out ib, out nb);

        // Always allocate the child its full natural size, anchored to the right
        // edge (top for a top panel, bottom otherwise). The child is never
        // re-laid-out, so it can't judder. snapshot() clips it to the animating
        // reveal fraction; overflow HIDDEN is the backstop for the full bounds.
        int x = width - cw_nat;
        int y = anchor_top ? 0 : height - ch_nat;
        var t = new Gsk.Transform ().translate ({ (float) x, (float) y });
        _child.allocate (cw_nat, ch_nat, baseline, t);
    }

    // The child is allocated (and the surface sized) to the full expanded extent
    // throughout the open cycle; the visible reveal is animated per frame via
    // queue_draw — pure GSK compositing, no surface resize.
    //
    // The reveal is a scale-from-corner bloom: the Control Center starts as a
    // small rectangle pinned to the tray-icon corner (right edge always; top for
    // a top panel, bottom otherwise) and scales up to full size as `fraction`
    // runs 0→1, with a slightly faster opacity fade so it solidifies before it
    // reaches full extent. The whole child scales as one unit, so there is no
    // reflow — it just grows out of the corner. (Replaces the earlier vertical
    // clip wipe, which read as the panel sliding up rather than blooming open.)
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
