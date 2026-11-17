// Example tray presenter: the Control Center tiles in a triangular surface
// that rises above the panel. Copy this folder to
// ~/.config/lumen-shell/extensions/tray-wedge/ and select it in extensions.json:
//   { "slots": { "tray.presenter": "tray-wedge" } }
//
// Every type lives in namespace TrayWedge (derived from the id) — the panel
// refuses to load an extension whose types live anywhere else.

public Lumen.Extension lumen_extension_new () {
    return new TrayWedge.Extension ();
}

namespace TrayWedge {

    const int PANEL_HEIGHT = 60;
    const int FADE_MS = 180;

    public class Extension : Lumen.Extension {
        public override void enable (Lumen.Context ctx) throws GLib.Error {
            ctx.provide (Lumen.SLOT_TRAY_PRESENTER,
                         new Presenter (ctx.param_int ("width"), ctx.param_int ("height")));
        }
    }

    public class Presenter : GLib.Object, Lumen.TrayPresenter {
        int width;
        int height;

        public Presenter (int width, int height) {
            this.width = width;
            this.height = height;
        }

        public Lumen.Tray create (Lumen.TrayModel model, Gtk.Window panel_window) {
            return new WedgeTray (model, panel_window, width, height);
        }
    }

    public class WedgeTray : GLib.Object, Lumen.Tray {
        Lumen.TrayModel model;
        Gtk.Window panel_window;
        int width;
        int height;
        Gtk.Button button;
        Lumen.ShapedSurface? surface = null;
        bool is_expanded = false;

        public bool expanded  { get { return is_expanded; } }
        public bool animating { get { return false; } }

        public WedgeTray (Lumen.TrayModel model, Gtk.Window panel_window, int width, int height) {
            this.model = model;
            this.panel_window = panel_window;
            this.width = width;
            this.height = height;

            button = new Gtk.Button.from_icon_name ("pan-up-symbolic");
            button.add_css_class ("circular");
            button.valign = Gtk.Align.CENTER;
            button.margin_end = 8;
            button.clicked.connect (toggle);
        }

        public Gtk.Widget? strip_widget () {
            return button;
        }

        public void toggle () {
            if (is_expanded) collapse (); else open ();
        }

        public void collapse () {
            if (!is_expanded) return;
            surface.dismiss (FADE_MS);
            set_expanded (false);
        }

        // Own surface: nothing to keep clickable on the panel itself.
        public void input_rects (Gtk.Window panel_window, Cairo.Region region) {}

        void open () {
            if (surface == null) surface = build_surface ();
            surface.reveal (FADE_MS);
            set_expanded (true);
        }

        void set_expanded (bool v) {
            is_expanded = v;
            notify_property ("expanded");
            expanded_changed ();
        }

        Lumen.ShapedSurface build_surface () {
            var path = "M0 %d L%d 0 L%d %d Z".printf (height, width / 2, width, height);
            var s = new Lumen.ShapedSurface (panel_window.application, "lumen-tray-wedge",
                                             Lumen.Edge.BOTTOM, width, height, path);
            s.set_margin (Lumen.Edge.BOTTOM, PANEL_HEIGHT);
            var ps = panel_window.get_surface ();
            if (ps != null) s.set_output (panel_window.get_display ().get_monitor_at_surface (ps));

            // The largest rectangle inside the triangle: half its width and
            // half its height, centred on the base.
            var tiles = new Gtk.FlowBox ();
            tiles.selection_mode = Gtk.SelectionMode.NONE;
            tiles.homogeneous = true;
            tiles.column_spacing = 8;
            tiles.row_spacing = 8;
            foreach (var m in model.modules) tiles.append (m.home_tile ());

            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = tiles;
            scroll.set_size_request (width / 2, height / 2);
            scroll.halign = Gtk.Align.CENTER;
            scroll.valign = Gtk.Align.END;

            s.content = scroll;
            s.pointer_left.connect (collapse);
            return s;
        }
    }
}
