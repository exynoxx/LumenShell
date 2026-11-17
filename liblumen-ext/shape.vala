namespace Lumen {

    public enum Edge { TOP, BOTTOM, LEFT, RIGHT }

    // A layer-shell surface clipped to an SVG path, with a matching input
    // region. Layer-shell stays an implementation detail: extensions compiled
    // against the vapi never need the gtk4-layer-shell vapi.
    public class ShapedSurface : Gtk.Window {

        public signal void pointer_left ();

        // Filled inside the path, behind the content.
        public Gdk.RGBA background { get; set; default = { 0.11f, 0.11f, 0.13f, 0.92f }; }

        public Gtk.Widget? content {
            get { return child; }
            set { child = value; }
        }

        Gsk.Path path;
        Cairo.Region region;
        bool region_applied = false;

        uint tick_id = 0;
        double fade_from;
        double fade_to;
        int64 fade_start;
        int fade_ms;

        public ShapedSurface (Gtk.Application app, string ns, Edge anchor,
                              int width, int height, string svg_path_data) {
            GLib.Object (application: app);

            path = Gsk.Path.parse (svg_path_data);
            if (path == null) {
                warning ("ShapedSurface %s: bad path data, using a rectangle", ns);
                var b = new Gsk.PathBuilder ();
                b.add_rect ({ { 0, 0 }, { width, height } });
                path = b.to_path ();
            }
            region = bands (path, width, height, 4);

            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_namespace (this, ns);
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
            GtkLayerShell.set_anchor (this, ls_edge (anchor), true);
            GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
            GtkLayerShell.set_exclusive_zone (this, 0);
            set_default_size (width, height);

            add_css_class ("lumen-shaped");
            install_css ();

            var motion = new Gtk.EventControllerMotion ();
            motion.leave.connect (() => pointer_left ());
            ((Gtk.Widget) this).add_controller (motion);
        }

        public void set_margin (Edge edge, int px) {
            GtkLayerShell.set_margin (this, ls_edge (edge), px);
        }

        public void set_output (Gdk.Monitor? monitor) {
            GtkLayerShell.set_monitor (this, monitor);
        }

        public void reveal (int ms) {
            if (!visible) opacity = 0;
            present ();
            fade (1, ms);
        }

        public void dismiss (int ms) {
            if (visible) fade (0, ms);
        }

        void fade (double target, int ms) {
            if (tick_id != 0) remove_tick_callback (tick_id);
            fade_from = opacity;
            fade_to = target;
            fade_ms = int.max (ms, 1);
            fade_start = -1;
            tick_id = add_tick_callback ((w, clock) => {
                int64 now = clock.get_frame_time ();
                if (fade_start < 0) fade_start = now;
                double t = double.min ((now - fade_start) / 1000.0 / fade_ms, 1);
                opacity = fade_from + (fade_to - fade_from) * t;
                if (t < 1) return GLib.Source.CONTINUE;
                tick_id = 0;
                if (fade_to == 0) visible = false;
                return GLib.Source.REMOVE;
            });
        }

        public override void snapshot (Gtk.Snapshot s) {
            s.push_fill (path, Gsk.FillRule.WINDING);
            s.append_color (background, { { 0, 0 }, { get_width (), get_height () } });
            base.snapshot (s);
            s.pop ();
        }

        // The region is fixed (fixed size), so it goes on once per realize.
        public override void size_allocate (int w, int h, int baseline) {
            base.size_allocate (w, h, baseline);
            var surface = get_surface ();
            if (!region_applied && surface != null) {
                surface.set_input_region (region);
                region_applied = true;
            }
        }

        public override void unrealize () {
            region_applied = false;
            base.unrealize ();
        }

        // Path rasterised into `band`-px-tall horizontal strips (one rect per
        // inside run, sampled on the band's middle row), for the input region.
        public static Cairo.Region bands (Gsk.Path path, int width, int height, int band) {
            var r = new Cairo.Region ();
            for (int y0 = 0; y0 < height; y0 += band) {
                int bh = int.min (band, height - y0);
                float py = y0 + bh / 2.0f;
                int run = -1;
                for (int x = 0; x <= width; x++) {
                    bool inside = x < width && path.in_fill ({ x + 0.5f, py }, Gsk.FillRule.WINDING);
                    if (inside && run < 0) {
                        run = x;
                    } else if (!inside && run >= 0) {
                        r.union_rectangle ({ run, y0, x - run, bh });
                        run = -1;
                    }
                }
            }
            return r;
        }

        static GtkLayerShell.Edge ls_edge (Edge e) {
            switch (e) {
                case Edge.TOP:    return GtkLayerShell.Edge.TOP;
                case Edge.LEFT:   return GtkLayerShell.Edge.LEFT;
                case Edge.RIGHT:  return GtkLayerShell.Edge.RIGHT;
                default:          return GtkLayerShell.Edge.BOTTOM;
            }
        }

        static bool css_installed = false;

        static void install_css () {
            var display = Gdk.Display.get_default ();
            if (css_installed || display == null) return;
            var css = new Gtk.CssProvider ();
            css.load_from_string ("window.lumen-shaped { background: none; box-shadow: none; }");
            Gtk.StyleContext.add_provider_for_display (display, css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            css_installed = true;
        }
    }
}
