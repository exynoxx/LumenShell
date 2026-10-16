// Recycled by FileColumn's ListView: setting `entry` invalidates icon and layout.

namespace LumenDesktop {

    public class FileRow : Gtk.Widget {

        public const int ROW_HEIGHT = 28;
        private const int ICON_SIZE = 16;
        private const int PAD_X     = 8;
        private const int GAP       = 8;
        private const int CHEVRON_W = 10;

        private FsEntry? _entry = null;
        public FsEntry? entry {
            get { return _entry; }
            set {
                if (_entry == value) return;
                _entry = value;
                icon_paintable = null;
                invalidate_layout();
                if (_entry != null) load_icon();
                queue_resize();
            }
        }

        private bool _selected = false;
        public bool selected {
            get { return _selected; }
            set { if (_selected != value) { _selected = value; queue_draw(); } }
        }

        private Gdk.Paintable? icon_paintable = null;

        // Cached: snapshot() runs per frame per row; re-wrapped only on width change.
        private Pango.Layout? layout = null;
        private int layout_width = int.MIN;
        private int natural_text_w = -1;

        public FileRow() {
            hexpand = true;
        }

        private void invalidate_layout() {
            layout = null;
            layout_width = int.MIN;
            natural_text_w = -1;
        }

        public override void css_changed(Gtk.CssStyleChange change) {
            base.css_changed(change);
            invalidate_layout();
        }

        // width -1 = unconstrained natural width.
        private unowned Pango.Layout text_layout(int width) {
            if (layout == null) {
                layout = create_pango_layout(_entry == null ? "" : _entry.display_name);
                layout.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
                layout_width = int.MIN;
            }
            if (layout_width != width) {
                layout_width = width;
                layout.set_width(width < 0 ? -1 : width * Pango.SCALE);
            }
            return layout;
        }

        private void load_icon() {
            if (_entry == null || _entry.icon == null) return;
            var display = Gdk.Display.get_default();
            if (display == null) return;
            var theme = Gtk.IconTheme.get_for_display(display);
            icon_paintable = theme.lookup_by_gicon(
                _entry.icon, ICON_SIZE, scale_factor,
                Gtk.TextDirection.NONE, Gtk.IconLookupFlags.FORCE_SYMBOLIC);
        }

        public override Gtk.SizeRequestMode get_request_mode() {
            return Gtk.SizeRequestMode.CONSTANT_SIZE;
        }

        public override void measure(Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = -1;
            natural_baseline = -1;
            if (orientation == Gtk.Orientation.VERTICAL) {
                minimum = ROW_HEIGHT;
                natural = ROW_HEIGHT;
                return;
            }
            if (natural_text_w < 0) {
                int tw, th;
                text_layout(-1).get_pixel_size(out tw, out th);
                natural_text_w = tw;
            }
            int want = PAD_X * 2 + ICON_SIZE + GAP + natural_text_w + GAP + CHEVRON_W;
            // Modest minimum so a long name doesn't blow up the column.
            minimum = int.min(want, 120);
            natural = want;
        }

        public override void snapshot(Gtk.Snapshot s) {
            int w = get_width();
            int h = get_height();
            if (w <= 0 || h <= 0 || _entry == null) return;

            if (_selected) {
                var r = Graphene.Rect();
                r.init(2, 1, w - 4, h - 2);
                var rr = Gsk.RoundedRect();
                rr.init_from_rect(r, 6);
                s.push_rounded_clip(rr);
                s.append_color({ 1.0f, 1.0f, 1.0f, 0.16f }, r);
                s.pop();
            }

            int x = PAD_X;

            if (icon_paintable != null) {
                s.save();
                var pt = Graphene.Point();
                pt.init(x, (h - ICON_SIZE) / 2);
                s.translate(pt);
                icon_paintable.snapshot(s, ICON_SIZE, ICON_SIZE);
                s.restore();
            }
            x += ICON_SIZE + GAP;

            int text_w = int.max(0, w - x - PAD_X - (_entry.is_dir ? CHEVRON_W + GAP : 0));
            unowned var l = text_layout(text_w);
            int tw, th;
            l.get_pixel_size(out tw, out th);

            var fg = Gdk.RGBA() { red = 1.0f, green = 1.0f, blue = 1.0f, alpha = 0.92f };
            s.save();
            var tp = Graphene.Point();
            tp.init(x, (h - th) / 2);
            s.translate(tp);
            s.append_layout(l, fg);
            s.restore();

            if (_entry.is_dir) draw_chevron(s, w - PAD_X - CHEVRON_W, h);
        }

        private void draw_chevron(Gtk.Snapshot s, int x, int h) {
            var color = Gdk.RGBA() { red = 1.0f, green = 1.0f, blue = 1.0f, alpha = 0.45f };
            var builder = new Gsk.PathBuilder();
            float cy = h / 2.0f;
            builder.move_to(x + 2.0f, cy - 4.0f);
            builder.line_to(x + 6.0f, cy);
            builder.line_to(x + 2.0f, cy + 4.0f);
            var stroke = new Gsk.Stroke(1.5f);
            stroke.set_line_cap(Gsk.LineCap.ROUND);
            stroke.set_line_join(Gsk.LineJoin.ROUND);
            s.append_stroke(builder.to_path(), stroke, color);
        }
    }
}
