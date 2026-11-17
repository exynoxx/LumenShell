// Snapshot helpers shared by the custom-drawn widgets. Needs gtk4 only.
namespace LumenCommon {
    public class Draw {
        public static Gdk.RGBA rgba(float r, float g, float b, float a) {
            return { r, g, b, a };
        }

        // Solid (optionally rounded) rectangle. radius <= 0 skips the clip node.
        public static void fill_rounded(Gtk.Snapshot s, float x, float y, float w, float h,
                                        float radius, Gdk.RGBA color) {
            var rect = Graphene.Rect();
            rect.init(x, y, w, h);
            if (radius <= 0) {
                s.append_color(color, rect);
                return;
            }
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(rect, radius);
            s.push_rounded_clip(rr);
            s.append_color(color, rect);
            s.pop();
        }

        public static Pango.Layout text_layout(Gtk.Widget w, string text, double size_pt,
                                               Pango.Weight weight = Pango.Weight.NORMAL) {
            var layout = w.create_pango_layout(text);
            var attrs = new Pango.AttrList();
            attrs.insert(Pango.AttrSize.new_absolute((int) (size_pt * Pango.SCALE)));
            attrs.insert(Pango.attr_weight_new(weight));
            layout.set_attributes(attrs);
            return layout;
        }

        public static void draw_layout(Gtk.Snapshot s, Pango.Layout layout,
                                       float x, float y, Gdk.RGBA color) {
            var pt = Graphene.Point();
            pt.init(x, y);
            s.save();
            s.translate(pt);
            s.append_layout(layout, color);
            s.restore();
        }
    }
}
