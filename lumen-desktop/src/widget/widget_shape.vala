// The frame is not a stroke: the silhouette is filled with the border colour
// and content clipped to a smaller opening, so each shape picks its own inner
// corner radius.

namespace LumenDesktop {

    public abstract class WidgetShape : GLib.Object {

        // Extra chrome above the opening: the folder tab, or a heavier top edge.
        protected float top_extra;

        // Implementations must push exactly one clip node.
        public abstract void push_clip(Gtk.Snapshot s, int w, int h);

        // Called right after push_clip, so a plain rect fill suffices.
        public virtual void fill(Gtk.Snapshot s, int w, int h, Gdk.RGBA color) {
            var r = Graphene.Rect();
            r.init(0, 0, w, h);
            s.append_color(color, r);
        }

        // CSS order: top, right, bottom, left.
        public virtual float[] frame_insets(float border) {
            return { border + top_extra, border, border, border };
        }

        // Implementations must push exactly one clip node.
        public abstract void push_content_clip(Gtk.Snapshot s, int w, int h, float[] frame);

        // Pin / close band: inside the silhouette, outside the content opening.
        public virtual Cairo.RectangleInt chrome_rect(int w, int h, float border) {
            return Cairo.RectangleInt() {
                x = 0, y = 0,
                width = w,
                height = (int) (top_extra + border)
            };
        }

        // Feeds the input region: a shape that doesn't fill its box (the
        // folder's tab strip) must report only the parts it does.
        public virtual Cairo.RectangleInt[] hit_rects(int w, int h) {
            return { Cairo.RectangleInt() { x = 0, y = 0, width = w, height = h } };
        }

        // Drawn over the content inside the content clip, so it hugs the opening.
        public abstract void inner_shadow(Gtk.Snapshot s, int w, int h, float[] frame,
                                          Gdk.RGBA color, float blur, float spread);

        public static WidgetShape from_spec(string name, double radius,
                                            double top_extra, double tab_ratio) {
            switch (name) {
                case "folder":
                case "":
                    return new FolderShape((float) radius, (float) top_extra, (float) tab_ratio);
                case "rounded-rect":
                case "rounded-rectangle":
                    return new RoundedRectShape((float) radius, (float) top_extra);
                case "rect":
                case "square":
                    return new RoundedRectShape(0, (float) top_extra);
                case "pill":
                    // Radius resolved at draw time from the height.
                    return new RoundedRectShape(-1, (float) top_extra);
                default:
                    warning("lumen-desktop: unknown widget shape '%s', using folder", name);
                    return new FolderShape((float) radius, (float) top_extra, (float) tab_ratio);
            }
        }
    }

    // Negative radius means pill (half the height), as in lumen-osd's Pill.
    public class RoundedRectShape : WidgetShape {

        protected float radius;

        public RoundedRectShape(float radius, float top_extra = 0) {
            this.radius = radius;
            this.top_extra = top_extra;
        }

        protected float effective_radius(int w, int h) {
            if (radius < 0) return h / 2.0f;
            // Never let the radius exceed half the smaller side, or GSK draws
            // a distorted silhouette.
            return float.min(radius, float.min(w, h) / 2.0f);
        }

        private Gsk.RoundedRect rounded(int w, int h) {
            var r = Graphene.Rect();
            r.init(0, 0, w, h);
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(r, effective_radius(w, h));
            return rr;
        }

        // ONE inner radius from the thinnest side: per-corner shrinking (as
        // append_border does) bulges the corners on an asymmetric frame's heavy side.
        protected Gsk.RoundedRect opening(int w, int h, float[] frame) {
            float top = frame[0], right = frame[1], bottom = frame[2], left = frame[3];
            float iw = float.max(0, w - left - right);
            float ih = float.max(0, h - top - bottom);

            var r = Graphene.Rect();
            r.init(left, top, iw, ih);

            float thinnest = float.min(float.min(left, right), float.min(top, bottom));
            float inner = float.max(0, effective_radius(w, h) - thinnest);
            inner = float.min(inner, float.min(iw, ih) / 2.0f);

            var rr = Gsk.RoundedRect();
            rr.init_from_rect(r, inner);
            return rr;
        }

        // Half-radius side inset: a glyph flush to the edge gets its top
        // corner sliced off by the silhouette's curve.
        public override Cairo.RectangleInt chrome_rect(int w, int h, float border) {
            int inset = (int) (effective_radius(w, h) * 0.5f);
            return Cairo.RectangleInt() {
                x = inset, y = 0,
                width = int.max(0, w - 2 * inset),
                height = (int) (top_extra + border)
            };
        }

        public override void push_clip(Gtk.Snapshot s, int w, int h) {
            s.push_rounded_clip(rounded(w, h));
        }

        public override void push_content_clip(Gtk.Snapshot s, int w, int h, float[] frame) {
            s.push_rounded_clip(opening(w, h, frame));
        }

        public override void inner_shadow(Gtk.Snapshot s, int w, int h, float[] frame,
                                          Gdk.RGBA color, float blur, float spread) {
            if (color.alpha <= 0 || (blur <= 0 && spread <= 0)) return;
            s.append_inset_shadow(opening(w, h, frame), color, 0, 0, spread, blur);
        }
    }

    public class FolderShape : RoundedRectShape {

        private float tab_ratio;

        public FolderShape(float radius, float tab_height, float tab_ratio) {
            base(radius, tab_height);
            this.tab_ratio = tab_ratio.clamp(0.1f, 0.9f);
        }

        private float tab_height(int h) {
            return float.min(top_extra, h / 2.0f);
        }

        private float slant(int h) { return tab_height(h) * 0.55f; }

        private float tab_width(int w, int h) {
            float r = corner_radius(w, h);
            return (w * tab_ratio).clamp(2 * r + slant(h), w - 2 * r - slant(h));
        }

        private float corner_radius(int w, int h) {
            return float.min(effective_radius(w, h), (h - tab_height(h)) / 2.0f);
        }

        // html_arc_to() is canvas arcTo: it fillets concave joins too, which a
        // rounded rect can't express.
        private Gsk.Path outline(int w, int h) {
            float th = tab_height(h);
            float r = corner_radius(w, h);
            float sl = slant(h);
            float step_r = float.min(r * 0.5f, th * 0.5f);
            float tab_w = tab_width(w, h);

            var b = new Gsk.PathBuilder();
            b.move_to(0, r);                                  // left edge, below the tab corner
            b.html_arc_to(0, 0, tab_w, 0, r);                 // tab top-left
            b.html_arc_to(tab_w, 0, tab_w + sl, th, step_r);  // tab top-right
            b.html_arc_to(tab_w + sl, th, w, th, step_r);     // concave step onto the body
            b.html_arc_to(w, th, w, h, r);                    // body top-right
            b.html_arc_to(w, h, 0, h, r);                     // bottom-right
            b.html_arc_to(0, h, 0, 0, r);                     // bottom-left
            b.close();
            return b.to_path();
        }

        public override void push_clip(Gtk.Snapshot s, int w, int h) {
            s.push_fill(outline(w, h), Gsk.FillRule.WINDING);
        }

        public override void push_content_clip(Gtk.Snapshot s, int w, int h, float[] frame) {
            s.push_rounded_clip(opening(w, h, frame));
        }

        // The tab minus its slant (so a glyph never straddles the sloped edge),
        // inset by half the corner radius so the tab's curves don't clip glyphs.
        public override Cairo.RectangleInt chrome_rect(int w, int h, float border) {
            int inset = (int) (corner_radius(w, h) * 0.5f);
            return Cairo.RectangleInt() {
                x = inset, y = 0,
                width = int.max(0, (int) tab_width(w, h) - 2 * inset),
                height = (int) tab_height(h)
            };
        }

        public override Cairo.RectangleInt[] hit_rects(int w, int h) {
            int th = (int) tab_height(h);
            return {
                Cairo.RectangleInt() { x = 0, y = th, width = w, height = h - th },
                Cairo.RectangleInt() { x = 0, y = 0,
                                       width = (int) (tab_width(w, h) + slant(h)),
                                       height = th }
            };
        }
    }
}
