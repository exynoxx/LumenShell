namespace LumenDesktop {

    public class WidgetHost : Gtk.Widget {

        private class Placement {
            public DesktopWidget widget;
            public WidgetSpec spec;
            public int x;             // -1 = centre on this axis
            public int y;
            public int drag_x;        // resolved pixel origin at drag start
            public int drag_y;

            public Placement(DesktopWidget widget, WidgetSpec spec, int x, int y) {
                this.widget = widget;
                this.spec = spec;
                this.x = x;
                this.y = y;
            }
        }

        private GLib.GenericArray<Placement> placements
            = new GLib.GenericArray<Placement>();

        private string monitor_key;   // connector name, or "default"

        // Lets the window re-clip its input region (live during a drag).
        public signal void layout_changed();

        public signal void widget_removed(WidgetSpec spec);

        public WidgetHost(WidgetSpec[] specs, string monitor_key) {
            this.monitor_key = monitor_key;

            foreach (var spec in specs) {
                var w = WidgetRegistry.create(spec);
                if (w == null) continue;

                int px, py;
                spec.resolve_position(monitor_key, out px, out py);

                var p = new Placement(w, spec, px, py);
                placements.add(p);

                w.set_parent(this);
                wire(p);
            }
        }

        private void wire(Placement p) {
            p.widget.move_started.connect(() => {
                // Resolve "centred" into pixels so the drag has a fixed origin.
                var r = place(p, get_width(), get_height());
                p.drag_x = r.x;
                p.drag_y = r.y;
            });

            p.widget.move_delta.connect((dx, dy) => {
                p.x = p.drag_x + (int) dx;
                p.y = p.drag_y + (int) dy;
                queue_allocate();
            });

            p.widget.move_finished.connect(() => {
                // Persist the clamped position, not the raw drag offset.
                var r = place(p, get_width(), get_height());
                p.x = r.x;
                p.y = r.y;
                DesktopConfig.save_position(p.spec, monitor_key, r.x, r.y);
            });

            p.widget.close_requested.connect(() => widget_removed(p.spec));
        }

        public override void dispose() {
            for (int i = 0; i < placements.length; i++) {
                placements.get(i).widget.unparent();
            }
            placements = new GLib.GenericArray<Placement>();
            base.dispose();
        }

        public override Gtk.SizeRequestMode get_request_mode() {
            return Gtk.SizeRequestMode.CONSTANT_SIZE;
        }

        // Requests nothing, or the layer surface would shrink to the widgets.
        public override void measure(Gtk.Orientation orientation, int for_size,
                                     out int minimum, out int natural,
                                     out int minimum_baseline, out int natural_baseline) {
            minimum = 0;
            natural = 0;
            minimum_baseline = -1;
            natural_baseline = -1;
        }

        public override void size_allocate(int width, int height, int baseline) {
            for (int i = 0; i < placements.length; i++) {
                var p = placements.get(i);
                var r = place(p, width, height);
                p.widget.allocate(r.width, r.height, -1,
                    new Gsk.Transform().translate({ (float) r.x, (float) r.y }));
            }
            layout_changed();
        }

        // Clamped so a widget dragged past an edge still lands fully on screen.
        private Cairo.RectangleInt place(Placement p, int host_w, int host_h) {
            int cw = int.min(p.spec.width, host_w);
            int ch = int.min(p.spec.height, host_h);
            int cx = p.x >= 0 ? p.x : (host_w - cw) / 2;
            int cy = p.y >= 0 ? p.y : (host_h - ch) / 2;
            cx = int.max(0, int.min(cx, host_w - cw));
            cy = int.max(0, int.min(cy, host_h - ch));
            return Cairo.RectangleInt() { x = cx, y = cy, width = cw, height = ch };
        }

        // Shape rects, not bounding boxes, so the corner beside a folder tab
        // stays click-through.
        public Cairo.RectangleInt[] widget_rects() {
            Cairo.RectangleInt[] rects = {};
            int host_w = get_width();
            int host_h = get_height();
            if (host_w <= 0 || host_h <= 0) return rects;

            for (int i = 0; i < placements.length; i++) {
                var p = placements.get(i);
                var box = place(p, host_w, host_h);
                foreach (var hit in p.widget.shape.hit_rects(box.width, box.height)) {
                    hit.x += box.x;
                    hit.y += box.y;
                    rects += hit;
                }
            }
            return rects;
        }
    }
}
