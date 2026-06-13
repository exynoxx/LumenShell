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
    LogindService logind_service;
    GLib.GenericArray<PanelWindow> windows = new GLib.GenericArray<PanelWindow>();
    bool hotplug_wired = false;

    public void activate (Gtk.Application app) {
        this.app = app;

        PanelConfig.load();
        Theme.install();

        // Session/power bridge: owns logind, locks before suspend.
        logind_service = new LogindService();

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

    // Build a tray area. Only the host tray carries the SNI system tray (the
    // watcher is a singleton); secondary trays get every other page (WiFi,
    // Bluetooth, Battery, Sound, Clock, Exit) — each tray item owns its own
    // service instance, so duplicating the widgets across monitors is safe.
    TrayBar make_tray (bool with_sni) {
        var t = new TrayBar();
        if (with_sni) t.set_app_tray(new SysTray());
        t.add_paged(new WifiTray());
        t.add_paged(new BluetoothTray());
        t.add_paged(new BatteryTray());
        t.add_paged(new SoundTray());
        t.add_icon(new Clock());
        t.add_paged(new ExitTray(logind_service.bridge));
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
