public class App : GLib.Object {

    public const int ICON_ROW_HEIGHT = 60;
    // Lenient enough to forgive diagonal paths that clip the concave corner
    // between the strip and the expanded tray.
    public const uint COLLAPSE_DELAY_MS = 500;

    // Auto-hide leaves a SLIVER_PX handle on-screen as the reveal hot-zone.
    public const int SLIVER_PX = 4;
    public const int HIDDEN_MARGIN = -(ICON_ROW_HEIGHT - SLIVER_PX);
    public const int64 REVEAL_ANIM_US = 200000;

    Gtk.Application app;
    TrayBar tray;                            // the primary panel's tray area
    PanelService panel_service;              // session-bus ToggleTray (global hotkey)
    SniWatcher sni_watcher;                  // SNI registry singleton, shared by every SysTray
    TrayRegistry registry;                   // id → applet factory
    LogindBridge logind;

    // One instance each, shared by every panel's applets — see activate().
    WifiService         wifi_service;
    BluetoothService    bluetooth_service;
    SoundService        sound_service;
    BatteryService      battery_service;
    PowerProfileService power_profile_service;

    GLib.GenericArray<PanelWindow> windows = new GLib.GenericArray<PanelWindow>();
    bool hotplug_wired = false;

    public void activate (Gtk.Application app) {
        this.app = app;

        PanelConfig.load();
        Theme.install();

        // Power actions + Caffeine. Lock-on-suspend belongs to lumen-lockscreen.
        logind = new LogindBridge(false);

        // Owns one DBus name so it must exist exactly once; every panel's SysTray
        // renders from its shared item set.
        sni_watcher = new SniWatcher();
        sni_watcher.start();

        // Built once: the applet factory runs per output, so per-applet services would
        // multiply polling (and the RadioState re-apply) by the monitor count.
        wifi_service          = new WifiService();
        bluetooth_service     = new BluetoothService();
        sound_service         = new SoundService();
        battery_service       = new BatteryService();
        power_profile_service = new PowerProfileService();

        // Each factory builds a fresh applet so one id can be realized on several panels.
        registry = new TrayRegistry();
        registry.register("systray",   () => new SysTray(sni_watcher));
        registry.register("wifi",      () => new WifiTray(wifi_service));
        registry.register("bluetooth", () => new BluetoothTray(bluetooth_service));
        registry.register("battery",   () => new BatteryTray(battery_service, power_profile_service));
        registry.register("sound",     () => new SoundTray(sound_service));
        registry.register("clock",     () => new Clock());
        registry.register("exit",      () => new ExitTray(logind));

        // Bind foreign-toplevel before building any AppBar so replay happens
        // synchronously when each AppBar subscribes inside its constructor.
        ToplevelStore.instance.bind();

        tray = make_tray();

        // The panel surface only gets keys once clicked, so the global tray hotkey
        // arrives over DBus from a Wayfire [command] binding.
        panel_service = new PanelService(tray);
        panel_service.start();

        build_windows();

        if (PanelConfig.multi_monitor && !hotplug_wired) {
            var monitors = Gdk.Display.get_default().get_monitors();
            monitors.items_changed.connect((pos, removed, added) => rebuild_windows());
            hotplug_wired = true;
        }
    }

    TrayBar make_tray () {
        var t = new TrayBar(logind);
        foreach (var id in PanelConfig.tray_enabled_order()) {
            var applet = registry.create(id);
            if (applet != null) t.add(applet);
        }
        return t;
    }

    // The first monitor is the tray host; single-monitor mode builds one window
    // with monitor = null.
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
