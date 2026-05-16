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
    // actually click: the bottom 60px strip (AppBar + TrayBar icon row) plus
    // the revealer's bounding box when expanded. GtkPopovers are separate
    // xdg_popups and don't go through this region.
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

        // Revealer area (only when actually visible on screen).
        if (tray.revealer.reveal_child || tray.revealer.child_revealed) {
            double rx, ry;
            if (tray.revealer.translate_coordinates(win, 0, 0, out rx, out ry)) {
                int rw = tray.revealer.get_width();
                int rh = tray.revealer.get_height();
                if (rw > 0 && rh > 0) {
                    var page = Cairo.RectangleInt() {
                        x = (int) rx, y = (int) ry, width = rw, height = rh,
                    };
                    region.union_rectangle(page);
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
