using Gtk;

public class LumenChip : Gtk.Widget {

    string _text = "";
    Gdk.RGBA _bg   = Utils.rgba(0.11f, 0.13f, 0.19f, 1f);
    Gdk.RGBA _fg   = Utils.rgba(0.52f, 0.52f, 0.57f, 1f);

    public LumenChip () {
        height_request = 24;
    }

    public void set_text_color (Gdk.RGBA color) {
        _fg = color;
        queue_draw();
    }

    public new void set_text (string text) {
        if (text == _text) return;
        _text = text;
        queue_resize();
        queue_draw();
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size,
                                  out int min, out int nat,
                                  out int min_baseline, out int nat_baseline) {
        min_baseline = -1; nat_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            var layout = create_pango_layout(_text);
            attach_size(layout, 12);
            int tw, th;
            layout.get_pixel_size(out tw, out th);
            min = nat = tw + 20;
        } else {
            min = nat = 24;
        }
    }

    void attach_size (Pango.Layout layout, int pt) {
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.AttrSize.new_absolute(pt * Pango.SCALE));
        attrs.insert(Pango.attr_weight_new(Pango.Weight.MEDIUM));
        layout.set_attributes(attrs);
    }

    public override void snapshot (Gtk.Snapshot s) {
        int w = get_width();
        int h = get_height();

        var rect = Graphene.Rect();
        rect.init(0, 0, w, h);
        var rr = Gsk.RoundedRect();
        rr.init_from_rect(rect, 12);
        s.push_rounded_clip(rr);
        s.append_color(_bg, rect);
        s.pop();

        var layout = create_pango_layout(_text);
        attach_size(layout, 12);
        int tw, th;
        layout.get_pixel_size(out tw, out th);
        var pt = Graphene.Point();
        pt.init(10, (h - th) / 2);
        s.save();
        s.translate(pt);
        s.append_layout(layout, _fg);
        s.restore();
    }
}
