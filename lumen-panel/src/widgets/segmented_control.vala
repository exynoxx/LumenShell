using Gtk;

// SegmentedControl — snapshot-drawn pill selector (Performance | Balanced | …).
// Modeled on WifiRow for click + hover and LumenProgressBar for rounded-rect
// drawing. One rounded track holds N equal segments; the selected segment is a
// filled accent pill, others draw dimmed labels with a faint hover highlight.
public class SegmentedControl : Gtk.Widget {

    public const int CTRL_H = 34;
    const int INSET = 3; // gap between the selected pill and the track edge

    string[] _labels = {};
    int _selected = -1;
    int _hovered  = -1;

    public signal void segment_selected (int index);

    static Gdk.RGBA track_col = Utils.rgba(0.10f, 0.11f, 0.16f, 1f);
    static Gdk.RGBA sel_bg    = Utils.rgba(0.10f, 0.24f, 0.62f, 0.95f);
    static Gdk.RGBA hov_bg    = Utils.rgba(0.17f, 0.18f, 0.24f, 0.85f);
    static Gdk.RGBA sel_fg    = Utils.rgba(0.96f, 0.97f, 1.0f,  1f);
    static Gdk.RGBA norm_fg   = Utils.rgba(0.60f, 0.62f, 0.70f, 1f);

    public SegmentedControl () {
        height_request = CTRL_H;
        hexpand = true;

        var click = new Gtk.GestureClick() { button = Gdk.BUTTON_PRIMARY };
        click.released.connect((n, x, y) => {
            int i = segment_at(x);
            if (i >= 0) segment_selected(i);
        });
        add_controller(click);

        var motion = new Gtk.EventControllerMotion();
        motion.motion.connect((x, y) => {
            int i = segment_at(x);
            if (i != _hovered) { _hovered = i; queue_draw(); }
        });
        motion.leave.connect(() => { _hovered = -1; queue_draw(); });
        add_controller(motion);
    }

    public int selected { get { return _selected; } }

    public void set_segments (string[] labels) {
        _labels = labels;
        if (_selected >= labels.length) _selected = -1;
        queue_draw();
    }

    public void set_selected (int index) {
        if (index == _selected) return;
        _selected = index;
        queue_draw();
    }

    private int segment_at (double x) {
        int n = _labels.length;
        if (n <= 0) return -1;
        int w = get_width();
        if (w <= 0) return -1;
        int i = (int) (x / ((double) w / n));
        return int.max(0, int.min(n - 1, i));
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size,
                                  out int min, out int nat,
                                  out int min_baseline, out int nat_baseline) {
        min_baseline = -1; nat_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            min = 200; nat = 360;
        } else {
            min = nat = CTRL_H;
        }
    }

    public override void snapshot (Gtk.Snapshot s) {
        int n = _labels.length;
        if (n <= 0) return;

        int w = get_width();
        int h = get_height();
        if (w <= 0 || h <= 0) return;

        // Track
        var track_rect = Graphene.Rect();
        track_rect.init(0, 0, w, h);
        var track_rr = Gsk.RoundedRect();
        track_rr.init_from_rect(track_rect, 10);
        s.push_rounded_clip(track_rr);
        s.append_color(track_col, track_rect);
        s.pop();

        float seg_w = (float) w / n;

        for (int i = 0; i < n; i++) {
            float sx = i * seg_w;

            if (i == _selected || (i == _hovered && i != _selected)) {
                var rect = Graphene.Rect();
                rect.init(sx + INSET, INSET, seg_w - INSET * 2, h - INSET * 2);
                var rr = Gsk.RoundedRect();
                rr.init_from_rect(rect, 8);
                s.push_rounded_clip(rr);
                s.append_color(i == _selected ? sel_bg : hov_bg, rect);
                s.pop();
            }

            var layout = create_pango_layout(_labels[i]);
            var attrs = new Pango.AttrList();
            attrs.insert(Pango.AttrSize.new_absolute(12 * Pango.SCALE));
            attrs.insert(Pango.attr_weight_new(
                i == _selected ? Pango.Weight.SEMIBOLD : Pango.Weight.NORMAL));
            layout.set_attributes(attrs);

            int tw, th;
            layout.get_pixel_size(out tw, out th);

            var pt = Graphene.Point();
            pt.init(sx + (seg_w - tw) / 2, (h - th) / 2);
            s.save();
            s.translate(pt);
            s.append_layout(layout, i == _selected ? sel_fg : norm_fg);
            s.restore();
        }
    }
}
