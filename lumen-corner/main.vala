const int TRIGGER_SIZE = 40;

class CornerApp : Gtk.Application {
    string[]? cli_slots;
    Gtk.Window? window;
    FileMonitor monitor;
    uint reload_id = 0;

    public CornerApp(string[]? cli_slots) {
        Object(application_id: "io.github.LumenCorner", flags: ApplicationFlags.NON_UNIQUE);
        this.cli_slots = cli_slots;
    }

    protected override void activate() {
        rebuild();
        watch_config();
        if (Environment.get_variable("LUMEN_CORNER_OPEN") != null) ((Ring) window.child).set_open(true);
    }

    void watch_config() {
        var file = Config.file();
        DirUtils.create_with_parents(file.get_parent().get_path(), 0755);
        try {
            monitor = file.monitor_file(FileMonitorFlags.NONE);
        } catch (Error e) {
            warning("watching %s: %s", file.get_path(), e.message);
            return;
        }
        // A save arrives as several events; rebuild once they settle.
        monitor.changed.connect(() => {
            if (reload_id != 0) Source.remove(reload_id);
            reload_id = Timeout.add(200, () => {
                reload_id = 0;
                rebuild();
                return Source.REMOVE;
            });
        });
    }

    // The new window is presented before the old one goes, so the
    // application never runs out of windows and quits.
    void rebuild() {
        var config = Config.load();
        var style = Style(config);
        var ring = new Ring(resolve_apps(cli_slots ?? config.slots), style);
        var old = window;
        window = create_corner_window(ring, style.outer_radius);
        ring.app_chosen.connect((chosen) => launch(chosen, window.get_display()));
        window.present();
        old?.destroy();
    }

    Gtk.Window create_corner_window(Ring ring, int size) {
        var win = new Gtk.ApplicationWindow(this) { child = ring };
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
}

AppInfo?[] resolve_apps(string[] desktop_ids) {
    var apps = new AppInfo?[Config.SLOT_COUNT];
    for (int i = 0; i < desktop_ids.length && i < Config.SLOT_COUNT; i++) {
        if (desktop_ids[i] != "") apps[i] = new DesktopAppInfo(desktop_ids[i]);
    }
    return apps;
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
    string[]? cli_slots = args.length > 1 ? args[1:args.length] : null;
    return new CornerApp(cli_slots).run(new string[] { args[0] });
}
