using Gtk;

// Snapshot-drawn progress bar matching the original DrawKit UiProgressBar.
// Rounded-rect track (always full width) + rounded-rect fill (proportional)
// + small percentage label centered vertically on the right side of the bar.
public class LumenProgressBar : Gtk.Widget {

    int _value = 0;

    public Gdk.RGBA track_color = Utils.rgba(0.10f, 0.11f, 0.16f, 1f);
    public Gdk.RGBA fill_color  = Utils.rgba(0.13f, 0.76f, 0.34f, 1f);
    public Gdk.RGBA text_color  = Utils.rgba(1f,    1f,    1f,    0.65f);

    public LumenProgressBar () {
        set_size_request(-1, 22);
        hexpand = true;
    }

    public int get_progress () { return _value; }

    public void set_progress (int v) {
        v = int.max(0, int.min(100, v));
        if (v == _value) return;
        _value = v;
        queue_draw();
    }

    public override void snapshot (Gtk.Snapshot s) {
        int w = get_width();
        int h = get_height();
        if (w <= 0 || h <= 0) return;

        float radius = (float) int.min(h / 2, 12);

        // Track
        var track_rect = Graphene.Rect();
        track_rect.init(0, 0, w, h);
        var track_rr = Gsk.RoundedRect();
        track_rr.init_from_rect(track_rect, radius);
        s.push_rounded_clip(track_rr);
        s.append_color(track_color, track_rect);
        s.pop();

        // Fill
        int fill_w = (int) (w * _value / 100.0f);
        if (fill_w > 0) {
            var fill_rect = Graphene.Rect();
            fill_rect.init(0, 0, fill_w, h);
            var fill_rr = Gsk.RoundedRect();
            fill_rr.init_from_rect(fill_rect, radius);
            s.push_rounded_clip(fill_rr);
            s.append_color(fill_color, fill_rect);
            s.pop();
        }

        // Embedded percentage label, right-aligned with 8 px inset.
        var layout = create_pango_layout(null);
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.AttrSize.new_absolute(11 * Pango.SCALE));
        layout.set_attributes(attrs);
        layout.set_text("%d%%".printf(_value), -1);

        int tw, th;
        layout.get_pixel_size(out tw, out th);

        var pt = Graphene.Point();
        pt.init(w - tw - 8, (h - th) / 2);
        s.save();
        s.translate(pt);
        s.append_layout(layout, text_color);
        s.restore();
    }
}
