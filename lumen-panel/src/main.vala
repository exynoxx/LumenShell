using Gtk;

public class App : GLib.Object {

    public const int ICON_ROW_HEIGHT = 60;

    Gtk.ApplicationWindow win;
    TrayBar tray;

    public void activate (Gtk.Application app) {
        win = new Gtk.ApplicationWindow(app);
        win.add_css_class("lumen-panel");
        win.set_default_size(-1, 60);

        GtkLayerShell.init_for_window(win);
        GtkLayerShell.set_namespace(win, "lumen-panel");
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT,   true);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT,  true);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_exclusive_zone(win, 60);
        GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.ON_DEMAND);

        Theme.install();

        // Bind foreign-toplevel before building the AppBar so replay happens
        // synchronously when AppBar subscribes inside its constructor.
        ToplevelStore.instance.bind();

        // Root: AppBar on the left, TrayBar on the right.
        var root = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
            hexpand = true, vexpand = true,
            valign = Gtk.Align.END,
        };

        var app_bar = new AppBar();
        root.append(app_bar);

        tray = new TrayBar();
        tray.add_paged(new WifiTray());
        tray.add_paged(new BatteryTray());
        tray.add_paged(new SoundTray());
        tray.add_icon(new Clock());
        tray.add_icon(new ExitTray());
        root.append(tray);

        win.set_child(root);
        win.present();

        // ESC anywhere on the panel collapses the tray. CAPTURE phase so
        // the window sees the key before any focused child can swallow it
        // (e.g. the WiFi password field).
        var esc = new Gtk.EventControllerKey();
        esc.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        esc.key_pressed.connect((keyval, keycode, mods) => {
            if (keyval == Gdk.Key.Escape && tray.is_expanded()) {
                tray.collapse();
                return true;
            }
            return false;
        });
        ((Gtk.Widget) win).add_controller(esc);

        // Collapse when the pointer leaves the panel surface entirely.
        // Watching contains-pointer on the *window* (not the tray) sidesteps
        // the transient-leave problem the tray motion controller had during
        // the reveal animation: the layer-shell window only grows by adding
        // input region, so a pointer that's inside before expansion stays
        // inside throughout. A short debounce absorbs any pointer flicker
        // when the input region updates mid-frame.
        uint leave_source = 0;
        var win_motion = new Gtk.EventControllerMotion();
        win_motion.notify["contains-pointer"].connect(() => {
            if (win_motion.contains_pointer) {
                if (leave_source != 0) {
                    GLib.Source.remove(leave_source);
                    leave_source = 0;
                }
                return;
            }
            if (!tray.is_expanded()) return;
            if (leave_source != 0) return;
            leave_source = GLib.Timeout.add(120, () => {
                leave_source = 0;
                if (!win_motion.contains_pointer && tray.is_expanded())
                    tray.collapse();
                return Source.REMOVE;
            });
        });
        ((Gtk.Widget) win).add_controller(win_motion);

        // Input region: re-apply when the surface is mapped/resized or the
        // tray reveals/hides its page area.
        // realize is a GTK4 method, not a signal; map fires after realize and
        // the GdkSurface is then attached, which is what update_input_region
        // needs. notify::default-height fires on each resize.
        win.notify["default-height"].connect(update_input_region);
        win.map.connect(update_input_region);
        tray.revealer.notify["child-revealed"].connect(update_input_region);
        tray.revealer.notify["reveal-child"].connect(update_input_region);
    }

    // Clip the layer-shell surface's input region to the parts the user can
    // actually click: the bottom 60px strip (AppBar + TrayBar icon row when
    // collapsed) plus the tray's full bounding box when expanded. The latter
    // is necessary because expanding pushes the tray's icon row UP, above
    // the bottom strip — without it, other tray icons become unclickable
    // while a page is open. GtkPopovers are separate xdg_popups and don't
    // go through this region.
    void update_input_region () {
        var gdk_surface = win.get_surface();
        if (gdk_surface == null) return;

        int sw = win.get_width();
        int sh = win.get_height();
        if (sw <= 0 || sh <= 0) return;

        var region = new Cairo.Region();

        // Bottom icon-row strip across the full width.
        var bottom = Cairo.RectangleInt() {
            x = 0,
            y = sh - ICON_ROW_HEIGHT,
            width = sw,
            height = ICON_ROW_HEIGHT,
        };
        region.union_rectangle(bottom);

        // Whole tray bounding box (icons + revealer) when expanded.
        if (tray.revealer.reveal_child || tray.revealer.child_revealed) {
            double tx, ty;
            if (tray.translate_coordinates(win, 0, 0, out tx, out ty)) {
                int tw = tray.get_width();
                int th = tray.get_height();
                if (tw > 0 && th > 0) {
                    var trect = Cairo.RectangleInt() {
                        x = (int) tx, y = (int) ty, width = tw, height = th,
                    };
                    region.union_rectangle(trect);
                }
            }
        }

        gdk_surface.set_input_region(region);
    }
}

int main (string[] args) {
    var app = new Gtk.Application("dev.lumen.panel", GLib.ApplicationFlags.DEFAULT_FLAGS);
    var holder = new App();
    app.activate.connect(() => holder.activate(app));
    return app.run(args);
}
