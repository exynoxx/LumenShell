using Gtk;
using Gee;

namespace LumenSettings {

    /* Snapshot-drawn monitor-arrangement canvas. Draws each enabled output as a
     * rounded rectangle scaled to fit; the user drags rectangles to reposition
     * them (with edge snapping). Modeled on the panel's SegmentedControl /
     * LumenProgressBar snapshot widgets. Operates directly on the page's working
     * OutputInfo list so position edits are visible to Apply. */
    public class DisplayArranger : Gtk.Widget {

        const int CANVAS_H = 220;
        const double PAD = 16.0;       // widget-px padding around the layout
        const double SNAP = 18.0;      // widget-px snap threshold

        Gee.ArrayList<OutputInfo> outs = new Gee.ArrayList<OutputInfo>();
        int selected = -1;
        int dragging = -1;
        int drag_start_x;              // dragged output's pos at drag begin (output px)
        int drag_start_y;

        // recomputed each snapshot, reused for hit-testing
        double sf = 1.0;               // output-px -> widget-px
        double off_x = 0;
        double off_y = 0;
        int min_x = 0;
        int min_y = 0;

        public signal void output_selected(string name);
        public signal void layout_changed();

        static Gdk.RGBA rgba(float r, float g, float b, float a) {
            var c = Gdk.RGBA();
            c.red = r; c.green = g; c.blue = b; c.alpha = a;
            return c;
        }
        static Gdk.RGBA canvas_bg = rgba(0.08f, 0.09f, 0.12f, 1f);
        static Gdk.RGBA rect_bg   = rgba(0.20f, 0.22f, 0.28f, 1f);
        static Gdk.RGBA rect_sel  = rgba(0.12f, 0.30f, 0.72f, 1f);
        static Gdk.RGBA rect_off  = rgba(0.14f, 0.15f, 0.18f, 1f);
        static Gdk.RGBA txt       = rgba(0.95f, 0.96f, 1.0f, 1f);
        static Gdk.RGBA txt_dim   = rgba(0.55f, 0.57f, 0.64f, 1f);

        public DisplayArranger() {
            hexpand = true;
            height_request = CANVAS_H;
            add_css_class("lumen-display-arranger");

            var drag = new Gtk.GestureDrag() { button = Gdk.BUTTON_PRIMARY };
            drag.drag_begin.connect(on_drag_begin);
            drag.drag_update.connect(on_drag_update);
            drag.drag_end.connect(on_drag_end);
            add_controller(drag);
        }

        public void set_outputs(Gee.ArrayList<OutputInfo> list) {
            outs = list;
            if (selected >= outs.size) selected = -1;
            if (selected < 0 && outs.size > 0) selected = 0;
            queue_draw();
        }

        public int selected_index() { return selected; }

        public void refresh() { queue_draw(); }

        public override Gtk.SizeRequestMode get_request_mode() {
            return Gtk.SizeRequestMode.CONSTANT_SIZE;
        }

        public override void measure(Gtk.Orientation orientation, int for_size,
                                     out int min, out int nat,
                                     out int min_baseline, out int nat_baseline) {
            min_baseline = -1; nat_baseline = -1;
            if (orientation == Gtk.Orientation.HORIZONTAL) { min = 360; nat = 560; }
            else { min = nat = CANVAS_H; }
        }

        // ---- coordinate transform -------------------------------------------

        void compute_transform() {
            int w = get_width(), h = get_height();
            int maxx = 0, maxy = 0;
            min_x = int.MAX; min_y = int.MAX;
            bool any = false;
            foreach (var o in outs) {
                if (!o.enabled || o.current_mode == null) continue;
                any = true;
                min_x = int.min(min_x, o.pos_x);
                min_y = int.min(min_y, o.pos_y);
                maxx = int.max(maxx, o.pos_x + o.eff_width());
                maxy = int.max(maxy, o.pos_y + o.eff_height());
            }
            if (!any) { sf = 1; off_x = off_y = 0; min_x = min_y = 0; return; }
            double world_w = double.max(1, maxx - min_x);
            double world_h = double.max(1, maxy - min_y);
            double avail_w = double.max(1, w - 2 * PAD);
            double avail_h = double.max(1, h - 2 * PAD);
            sf = double.min(avail_w / world_w, avail_h / world_h);
            off_x = (w - world_w * sf) / 2.0;
            off_y = (h - world_h * sf) / 2.0;
        }

        void rect_of(OutputInfo o, out double rx, out double ry,
                     out double rw, out double rh) {
            rx = off_x + (o.pos_x - min_x) * sf;
            ry = off_y + (o.pos_y - min_y) * sf;
            rw = o.eff_width() * sf;
            rh = o.eff_height() * sf;
        }

        int hit_test(double x, double y) {
            for (int i = outs.size - 1; i >= 0; i--) {
                var o = outs.get(i);
                if (!o.enabled || o.current_mode == null) continue;
                double rx, ry, rw, rh;
                rect_of(o, out rx, out ry, out rw, out rh);
                if (x >= rx && x <= rx + rw && y >= ry && y <= ry + rh) return i;
            }
            return -1;
        }

        // ---- drag handlers --------------------------------------------------

        void on_drag_begin(double x, double y) {
            compute_transform();
            int i = hit_test(x, y);
            dragging = i;
            if (i >= 0) {
                selected = i;
                drag_start_x = outs.get(i).pos_x;
                drag_start_y = outs.get(i).pos_y;
                output_selected(outs.get(i).name);
            }
            queue_draw();
        }

        void on_drag_update(double dx, double dy) {
            if (dragging < 0) return;
            var o = outs.get(dragging);
            o.pos_x = drag_start_x + (int) Math.round(dx / sf);
            o.pos_y = drag_start_y + (int) Math.round(dy / sf);
            snap(o);
            queue_draw();
            layout_changed();
        }

        void on_drag_end(double dx, double dy) {
            if (dragging < 0) return;
            normalize();
            dragging = -1;
            queue_draw();
            layout_changed();
        }

        // Snap the dragged output's edges to neighbours (in output px).
        void snap(OutputInfo o) {
            double thr = SNAP / sf;
            int ow = o.eff_width(), oh = o.eff_height();
            foreach (var n in outs) {
                if (n == o || !n.enabled || n.current_mode == null) continue;
                int nw = n.eff_width(), nh = n.eff_height();
                // horizontal abutment
                if (Math.fabs((o.pos_x) - (n.pos_x + nw)) < thr) o.pos_x = n.pos_x + nw;
                else if (Math.fabs((o.pos_x + ow) - n.pos_x) < thr) o.pos_x = n.pos_x - ow;
                // vertical abutment
                if (Math.fabs((o.pos_y) - (n.pos_y + nh)) < thr) o.pos_y = n.pos_y + nh;
                else if (Math.fabs((o.pos_y + oh) - n.pos_y) < thr) o.pos_y = n.pos_y - oh;
                // edge alignment (top/left)
                if (Math.fabs(o.pos_y - n.pos_y) < thr) o.pos_y = n.pos_y;
                if (Math.fabs(o.pos_x - n.pos_x) < thr) o.pos_x = n.pos_x;
            }
        }

        // Re-origin so the top-left of the bounding box is (0,0); resolve gross
        // overlaps of the dragged rect by nudging it to abut.
        void normalize() {
            int mx = int.MAX, my = int.MAX;
            foreach (var o in outs) {
                if (!o.enabled || o.current_mode == null) continue;
                mx = int.min(mx, o.pos_x);
                my = int.min(my, o.pos_y);
            }
            if (mx == int.MAX) return;
            foreach (var o in outs) {
                o.pos_x -= mx;
                o.pos_y -= my;
            }
        }

        // ---- drawing --------------------------------------------------------

        public override void snapshot(Gtk.Snapshot s) {
            int w = get_width(), h = get_height();
            if (w <= 0 || h <= 0) return;

            var full = Graphene.Rect();
            full.init(0, 0, w, h);
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(full, 10);
            s.push_rounded_clip(rr);
            s.append_color(canvas_bg, full);
            s.pop();

            compute_transform();

            for (int i = 0; i < outs.size; i++) {
                var o = outs.get(i);
                if (!o.enabled || o.current_mode == null) continue;
                double rx, ry, rw, rh;
                rect_of(o, out rx, out ry, out rw, out rh);

                var rect = Graphene.Rect();
                rect.init((float) (rx + 2), (float) (ry + 2),
                          (float) (rw - 4), (float) (rh - 4));
                var box = Gsk.RoundedRect();
                box.init_from_rect(rect, 6);
                s.push_rounded_clip(box);
                s.append_color(i == selected ? rect_sel : rect_bg, rect);
                s.pop();

                // label: name + resolution
                var layout = create_pango_layout(
                    "%s\n%s".printf(o.name, o.current_mode.res_key()));
                layout.set_alignment(Pango.Alignment.CENTER);
                var attrs = new Pango.AttrList();
                attrs.insert(Pango.AttrSize.new_absolute(11 * Pango.SCALE));
                layout.set_attributes(attrs);
                int tw, th;
                layout.get_pixel_size(out tw, out th);
                var pt = Graphene.Point();
                pt.init((float) (rx + (rw - tw) / 2), (float) (ry + (rh - th) / 2));
                s.save();
                s.translate(pt);
                s.append_layout(layout, i == selected ? txt : txt_dim);
                s.restore();
            }
        }
    }
}
