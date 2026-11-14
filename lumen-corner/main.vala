const int MAX_APPS = 4;
const int TRIGGER_SIZE = 40;

const string[] DEFAULT_APPS = {
    "org.gnome.Nautilus.desktop", "firefox.desktop",
    "org.gnome.Terminal.desktop", "org.gnome.Settings.desktop",
    "org.gnome.Ptyxis.desktop", "kitty.desktop", "foot.desktop",
};

AppInfo[] resolve_apps(string[] desktop_ids) {
    AppInfo[] apps = {};
    foreach (var id in desktop_ids) {
        var info = new DesktopAppInfo(id);
        if (info != null) apps += info;
        if (apps.length == MAX_APPS) break;
    }
    return apps;
}

Gtk.Window create_corner_window(Gtk.Application app, Ring ring, int size) {
    var win = new Gtk.ApplicationWindow(app) { child = ring };
    GtkLayerShell.init_for_window(win);
    GtkLayerShell.set_namespace(win, "lumen-corner");
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY);
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, true);
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, true);
    GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE);

    var css = new Gtk.CssProvider();
    css.load_from_string("window { background: transparent; }");
    Gtk.StyleContext.add_provider_for_display(win.get_display(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

    win.map.connect(() => update_input_region(win, ring.is_open, size));
    ring.notify["is-open"].connect(() => update_input_region(win, ring.is_open, size));
    return win;
}

// ponytail: square input region while open; make it ring-shaped if clicks
// through the inner hole ever matter.
void update_input_region(Gtk.Window win, bool open, int size) {
    int s = open ? size : TRIGGER_SIZE;
    win.get_surface().set_input_region(new Cairo.Region.rectangle({ 0, size - s, s, s }));
}

void launch(AppInfo app, Gdk.Display display) {
    try {
        app.launch(null, display.get_app_launch_context());
    } catch (Error e) {
        warning("launch %s: %s", app.get_id(), e.message);
    }
}

int main(string[] args) {
    unowned string[] ids = args.length > 1 ? args[1:args.length] : DEFAULT_APPS;
    var app = new Gtk.Application("io.github.LumenCorner", ApplicationFlags.NON_UNIQUE);
    app.activate.connect(() => {
        var apps = resolve_apps(ids);
        if (apps.length == 0) {
            warning("no launchable apps found");
            return;
        }
        var style = Style.load();
        var ring = new Ring(apps, style);
        var win = create_corner_window(app, ring, style.outer_radius);
        ring.app_chosen.connect((chosen) => launch(chosen, win.get_display()));
        win.present();
        if (Environment.get_variable("LUMEN_CORNER_OPEN") != null) ring.set_open(true);
    });
    return app.run(new string[] { args[0] });
}
