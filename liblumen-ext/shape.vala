namespace Lumen {

    public enum Edge { TOP, BOTTOM, LEFT, RIGHT }

    // A layer-shell surface clipped to an SVG path, with a matching input region.
    // STUB — implemented in a later task.
    public class ShapedSurface : Gtk.Window {

        public signal void pointer_left ();

        public ShapedSurface (Gtk.Application app, string ns, Edge anchor,
                              int width, int height, string svg_path_data) {
            GLib.Object (application: app);
        }

        public Gtk.Widget? content { get; set; }

        public void reveal (int ms) {}
        public void dismiss (int ms) {}

        // Path rasterised into `band`-px-tall horizontal strips (one rect per
        // inside run), for the Wayland input region.
        public static Cairo.Region bands (Gsk.Path path, int width, int height, int band) {
            return new Cairo.Region ();
        }
    }
}
