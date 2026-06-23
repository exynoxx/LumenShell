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
    TrayBar tray;                            // the primary panel's tray area
    SniWatcher sni_watcher;                  // SNI registry singleton, shared by every SysTray
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

        // The SNI watcher owns a single DBus name (org.kde.StatusNotifierWatcher)
        // and must exist exactly once, but its item registry feeds every panel's
        // SysTray widget. Create and start it once here; each SysTray factory
        // closes over it and renders its own icons from the shared set.
        sni_watcher = new SniWatcher();
        sni_watcher.start();

        // Build the applet registry once. Each factory creates a fresh applet
        // (its own widgets + service instances) so the same id can be realized
        // on multiple panels. Exit's factory closes over the logind bridge;
        // systray's closes over the shared SNI watcher.
        registry = new TrayRegistry();
        registry.register("systray",   () => new SysTray(sni_watcher));
        registry.register("wifi",      () => new WifiTray());
        registry.register("bluetooth", () => new BluetoothTray());
        registry.register("battery",   () => new BatteryTray());
        registry.register("sound",     () => new SoundTray());
        registry.register("clock",     () => new Clock());
        registry.register("exit",      () => new ExitTray(logind_service.bridge));

        // Bind foreign-toplevel before building any AppBar so replay happens
        // synchronously when each AppBar subscribes inside its constructor.
        ToplevelStore.instance.bind();

        tray = make_tray();

        build_windows();

        if (PanelConfig.multi_monitor && !hotplug_wired) {
            var monitors = Gdk.Display.get_default().get_monitors();
            monitors.items_changed.connect((pos, removed, added) => rebuild_windows());
            hotplug_wired = true;
        }
    }

    // Build a tray area from the user's configured order. Every panel gets the
    // full set of configured applets — including the SNI system tray, whose
    // widgets all share the one watcher. Each applet owns its own service
    // instance (and SysTray its own SniItem widgets), so duplicating across
    // monitors is safe.
    TrayBar make_tray () {
        var t = new TrayBar();
        foreach (var id in PanelConfig.tray_enabled_order()) {
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
            // The primary panel keeps the prebuilt tray; secondaries get their
            // own full tray (system tray included) only when the user enabled
            // tray-on-all-monitors.
            TrayBar? wtray = host ? tray
                : (PanelConfig.tray_all_monitors ? make_tray() : null);
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
