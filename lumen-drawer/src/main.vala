public class DrawerApp : Gtk.Application {

    private GLib.GenericArray<DrawerWindow> wins = new GLib.GenericArray<DrawerWindow>();
    private bool bound = false;
    private AppInfoMonitor app_monitor;   // keep a ref so it isn't collected
    private uint refresh_source = 0;

    construct {
        application_id = "dev.lumen.drawer";
    }

    protected override void activate() {
        if (!bound) {
            // Before any window maps, so focus_changed sees the initial state.
            DrawerToplevels.instance.bind();
            bound = true;

            // Grid geometry must be known before any window is built.
            LumenDrawer.DrawerConfig.load();

            build_windows();

            // Hides the grid if lumen-drawer restarted while peeked.
            LumenCommon.WayfireIpc.send_method("lumen-peek/stop");

            var monitors = Gdk.Display.get_default().get_monitors();
            monitors.items_changed.connect((p, r, a) => rebuild_windows());

            app_monitor = AppInfoMonitor.get();
            app_monitor.changed.connect(schedule_app_refresh);
        }
        for (int i = 0; i < wins.length; i++) wins.get(i).present();
    }

    // A package transaction fires `changed` many times; coalesce into one reload.
    private void schedule_app_refresh() {
        if (refresh_source != 0) GLib.Source.remove(refresh_source);
        refresh_source = GLib.Timeout.add(1500, () => {
            refresh_source = 0;
            for (int i = 0; i < wins.length; i++) wins.get(i).reload();
            return GLib.Source.REMOVE;
        });
    }

    // One per monitor: peeks are per-output, and an output with no grid
    // would reveal only the grey backdrop.
    void build_windows() {
        var monitors = Gdk.Display.get_default().get_monitors();
        uint n = monitors.get_n_items();
        if (n == 0) {
            wins.add(new DrawerWindow(this, null));
            return;
        }
        for (uint i = 0; i < n; i++) {
            var mon = monitors.get_item(i) as Gdk.Monitor;
            wins.add(new DrawerWindow(this, mon));
        }
    }

    void rebuild_windows() {
        for (int i = 0; i < wins.length; i++) wins.get(i).destroy();
        wins = new GLib.GenericArray<DrawerWindow>();
        build_windows();
        for (int i = 0; i < wins.length; i++) wins.get(i).present();
    }
}

int main(string[] args) {
    var app = new DrawerApp();
    return app.run(args);
}
