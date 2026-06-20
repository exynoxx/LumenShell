using Gtk;

public class App : GLib.Object {

    public const int ICON_ROW_HEIGHT = 60;
    // Grace period before the tray collapses after the pointer leaves the
    // bounded area. Lenient enough to forgive diagonal mouse paths that clip
    // the concave corner between the bottom strip and the expanded tray.
    public const uint COLLAPSE_DELAY_MS = 500;

    // Auto-hide: when enabled the panel slides off the bottom edge, leaving a
    // SLIVER_PX handle on-screen as the reveal hot-zone. Hidden state shifts the
    // surface down by HIDDEN_MARGIN via a negative layer-shell bottom margin.
    public const int SLIVER_PX = 4;
    public const int HIDDEN_MARGIN = -(ICON_ROW_HEIGHT - SLIVER_PX);
    public const int64 REVEAL_ANIM_US = 200000; // 200ms

    Gtk.Application app;
    TrayBar tray;                            // the one system tray (SNI singleton)
    TrayRegistry registry;                   // id → applet factory
    LogindService logind_service;
    GLib.GenericArray<PanelWindow> windows = new GLib.GenericArray<PanelWindow>();
    bool hotplug_wired = false;

    public void activate (Gtk.Application app) {
        this.app = app;

        PanelConfig.load();
        Theme.install();

        // Session/power bridge: owns logind, locks before suspend.
        logind_service = new LogindService();

        // Build the applet registry once. Each factory creates a fresh applet
        // (its own widgets + service instances) so the same id can be realized
        // on multiple panels. Exit's factory closes over the logind bridge.
        registry = new TrayRegistry();
        registry.register("systray",   () => new SysTray());
        registry.register("wifi",      () => new WifiTray());
        registry.register("bluetooth", () => new BluetoothTray());
        registry.register("battery",   () => new BatteryTray());
        registry.register("sound",     () => new SoundTray());
        registry.register("clock",     () => new Clock());
        registry.register("exit",      () => new ExitTray(logind_service.bridge));

        // Bind foreign-toplevel before building any AppBar so replay happens
        // synchronously when each AppBar subscribes inside its constructor.
        ToplevelStore.instance.bind();

        // The system tray (SNI watcher) is a singleton — it owns a single DBus
        // name and must exist exactly once — so it is built here and lives on
        // the primary panel. Secondary panels get their own tray (built per
        // window in build_windows) WITHOUT the SNI item when the user opts in.
        tray = make_tray(true);

        build_windows();

        if (PanelConfig.multi_monitor && !hotplug_wired) {
            var monitors = Gdk.Display.get_default().get_monitors();
            monitors.items_changed.connect((pos, removed, added) => rebuild_windows());
            hotplug_wired = true;
        }
    }

    // Build a tray area from the user's configured order. Only the host tray
    // carries the SNI system tray (the watcher is a singleton); secondary trays
    // skip "systray" but get every other configured applet — each tray item
    // owns its own service instance, so duplicating across monitors is safe.
    TrayBar make_tray (bool host) {
        var t = new TrayBar();
        foreach (var id in PanelConfig.tray_enabled_order()) {
            if (id == "systray" && !host) continue;   // SNI watcher is a singleton → host only
            var applet = registry.create(id);
            if (applet != null) t.add(applet);
        }
        return t;
    }

    // (Re)build the set of panel windows from the current monitor list. The
    // first monitor is the tray host. Single-monitor mode builds exactly one
    // window with monitor = null (behaviorally identical to the original panel).
    void build_windows () {
        if (!PanelConfig.multi_monitor) {
            windows.add(new PanelWindow(app, null, true, tray));
            return;
        }

        var monitors = Gdk.Display.get_default().get_monitors();
        uint n = monitors.get_n_items();
        if (n == 0) {
            // No monitors reported (yet) — fall back to one unpinned window so
            // the panel still appears; hotplug will rebuild when outputs arrive.
            windows.add(new PanelWindow(app, null, true, tray));
            return;
        }
        for (uint i = 0; i < n; i++) {
            var mon = monitors.get_item(i) as Gdk.Monitor;
            bool host = (i == 0);
            // Host keeps the singleton tray; secondaries get their own
            // SNI-less tray only when the user enabled tray-on-all-monitors.
            TrayBar? wtray = host ? tray
                : (PanelConfig.tray_all_monitors ? make_tray(false) : null);
            windows.add(new PanelWindow(app, mon, host, wtray));
        }
    }

    void rebuild_windows () {
        // Detach the shared tray from whichever window holds it so destroying
        // that window doesn't tear down the singleton SNI watcher.
        for (int i = 0; i < windows.length; i++) {
            windows.get(i).release_tray();
        }
        for (int i = 0; i < windows.length; i++) {
            windows.get(i).destroy();
        }
        windows = new GLib.GenericArray<PanelWindow>();
        build_windows();
    }
}

int main (string[] args) {
    var app = new Gtk.Application("dev.lumen.panel", GLib.ApplicationFlags.DEFAULT_FLAGS);
    var holder = new App();
    app.activate.connect(() => holder.activate(app));
    return app.run(args);
}
