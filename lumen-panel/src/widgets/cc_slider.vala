using Gtk;

// macOS Control Center slider: a thick rounded track, a bright fill, and a
// circular knob that overflows the track. Pure GSK (rounded clips + a filled
// circle path) — GPU-rasterized. Drag or click anywhere to set the value.
public class CcSlider : Gtk.Widget {

    const int H  = 26;   // widget height
    const int TH = 8;    // track height
    const int KR = 10;   // knob radius

    int _value = 0;
    double drag_start_x = 0;

    public signal void value_changed (int pct);

    static Gdk.RGBA track_col = Utils.rgba (1f, 1f, 1f, 0.16f);
    static Gdk.RGBA fill_col  = Utils.rgba (1f, 1f, 1f, 0.95f);
    static Gdk.RGBA knob_col  = Utils.rgba (1f, 1f, 1f, 1f);

    public CcSlider () {
        set_size_request (-1, H);
        hexpand = true;

        var drag = new Gtk.GestureDrag () { button = Gdk.BUTTON_PRIMARY };
        drag.drag_begin.connect ((x, y) => { drag_start_x = x; set_from_x (x); });
        drag.drag_update.connect ((ox, oy) => set_from_x (drag_start_x + ox));
        add_controller (drag);
    }

    public int get_value () { return _value; }

    public void set_value (int v) {
        v = v.clamp (0, 100);
        if (v == _value) return;
        _value = v;
        queue_draw ();
    }

    void set_from_x (double x) {
        int w = get_width ();
        if (w <= 0) return;
        double usable = w - TH;             // travel between the rounded track ends
        int v = (int) Math.round ((x - TH / 2.0) / usable * 100.0);
        v = v.clamp (0, 100);
        if (v != _value) {
            _value = v;
            queue_draw ();
            value_changed (v);
        }
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void snapshot (Gtk.Snapshot s) {
        int w = get_width ();
        if (w <= 0) return;

        float ty = (H - TH) / 2.0f;
        float radius = TH / 2.0f;

        // track
        var tr = Graphene.Rect ();
        tr.init (0, ty, w, TH);
        var trr = Gsk.RoundedRect ();
        trr.init_from_rect (tr, radius);
        s.push_rounded_clip (trr);
        s.append_color (track_col, tr);
        s.pop ();

        // knob center travels between the inset ends
        float kx = TH / 2.0f + (float) (_value / 100.0 * (w - TH));

        // fill up to the knob
        if (kx > 0) {
            var fr = Graphene.Rect ();
            fr.init (0, ty, kx, TH);
            var frr = Gsk.RoundedRect ();
            frr.init_from_rect (fr, radius);
            s.push_rounded_clip (frr);
            s.append_color (fill_col, fr);
            s.pop ();
        }

        // knob
        var kb = new Gsk.PathBuilder ();
        var c = Graphene.Point ();
        c.init (kx, H / 2.0f);
        kb.add_circle (c, KR);
        s.append_fill (kb.to_path (), Gsk.FillRule.WINDING, knob_col);
    }
}
