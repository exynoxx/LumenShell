using Gtk;

public class App : GLib.Object {

    public const int ICON_ROW_HEIGHT = 60;
    // Grace period before the tray collapses after the pointer leaves the
    // bounded area. Lenient enough to forgive diagonal mouse paths that clip
    // the concave corner between the bottom strip and the expanded tray.
    public const uint COLLAPSE_DELAY_MS = 500;

    Gtk.ApplicationWindow win;
    TrayBar tray;
    uint collapse_timeout_id = 0;
    uint resize_tick_id = 0;

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

        // Input region: re-apply when the surface is mapped or the tray
        // reveals/hides its page area. The revealer notify hooks fire only
        // at the start and end of the animation; the layer-shell surface
        // grows incrementally between those two points. While the
        // transition is in progress, a tick callback re-applies the input
        // region every frame so it stays aligned with the new buffer size.
        // Without this, the input region remains in old surface
        // coordinates during the resize and the compositor fires a
        // wl_pointer.leave when the cursor's new surface-local position
        // lands outside the stale region — with a stationary mouse no
        // matching enter follows, so the hover-out timer collapses the
        // tray right after click.
        win.map.connect(update_input_region);
        tray.revealer.notify["reveal-child"].connect(() => {
            update_input_region();
            start_resize_tracking();
        });
        tray.revealer.notify["child-revealed"].connect(update_input_region);

        // Hover-out collapse. contains-pointer on a window-level motion
        // controller is the right signal source provided the input region
        // tracks the surface size (see above).
        var win_motion = new Gtk.EventControllerMotion();
        win_motion.notify["contains-pointer"].connect(() => {
            if (win_motion.contains_pointer) { cancel_collapse(); return; }
            if (tray.is_expanded()) schedule_collapse();
        });
        ((Gtk.Widget) win).add_controller(win_motion);
    }

    void start_resize_tracking () {
        if (resize_tick_id != 0) return;
        resize_tick_id = ((Gtk.Widget) win).add_tick_callback((widget, clock) => {
            update_input_region();
            if (tray.revealer.reveal_child == tray.revealer.child_revealed) {
                resize_tick_id = 0;
                return GLib.Source.REMOVE;
            }
            return GLib.Source.CONTINUE;
        });
    }

    void schedule_collapse () {
        if (collapse_timeout_id != 0) return;
        collapse_timeout_id = GLib.Timeout.add(COLLAPSE_DELAY_MS, () => {
            collapse_timeout_id = 0;
            if (tray.is_expanded()) tray.collapse();
            return GLib.Source.REMOVE;
        });
    }

    void cancel_collapse () {
        if (collapse_timeout_id == 0) return;
        GLib.Source.remove(collapse_timeout_id);
        collapse_timeout_id = 0;
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

        var bottom = Cairo.RectangleInt() {
            x = 0,
            y = sh - ICON_ROW_HEIGHT,
            width = sw,
            height = ICON_ROW_HEIGHT,
        };
        region.union_rectangle(bottom);

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
