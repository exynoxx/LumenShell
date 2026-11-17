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
    LogindBridge logind;

    // One instance each, shared by every panel's applets — see activate().
    WifiService         wifi_service;
    BluetoothService    bluetooth_service;
    SoundService        sound_service;
    BatteryService      battery_service;
    PowerProfileService power_profile_service;
    BrightnessService   brightness_service;     // polls sysfs only while a slider is mapped

    GLib.GenericArray<PanelWindow> windows = new GLib.GenericArray<PanelWindow>();

    public void activate (Gtk.Application app) {
        if (this.app != null) return;        // second launch of the unique app: already running
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
        // multiply polling by the monitor count.
        wifi_service          = new WifiService();
        bluetooth_service     = new BluetoothService();
        sound_service         = new SoundService();
        battery_service       = new BatteryService();
        power_profile_service = new PowerProfileService();
        brightness_service    = new BrightnessService();
        battery_service.ac_changed.connect(power_profile_service.refresh);

        // Bind foreign-toplevel before building any AppBar so replay happens
        // synchronously when each AppBar subscribes inside its constructor.
        ToplevelStore.instance.bind();

        tray = make_tray();

        // The panel surface only gets keys once clicked, so the global tray hotkey
        // arrives over DBus from a Wayfire [command] binding.
        panel_service = new PanelService(tray);
        panel_service.start();

        build_windows();

        if (PanelConfig.multi_monitor) {
            var monitors = Gdk.Display.get_default().get_monitors();
            monitors.items_changed.connect((pos, removed, added) => rebuild_windows());
        }
    }

    TrayBar make_tray () {
        var t = new TrayBar(logind, brightness_service);
        // A fresh applet per call so one id can be realized on several panels.
        foreach (var id in PanelConfig.tray_enabled_order()) {
            ITrayApplet? applet = null;
            switch (id) {
                case "search":    if (Environment.find_program_in_path("lumen-search") != null) applet = new SearchTray(); break;
                case "systray":   applet = new SysTray(sni_watcher); break;
                case "wifi":      applet = new WifiTray(wifi_service); break;
                case "bluetooth": applet = new BluetoothTray(bluetooth_service); break;
                case "battery":   applet = new BatteryTray(battery_service, power_profile_service); break;
                case "sound":     applet = new SoundTray(sound_service); break;
                case "clock":     applet = new Clock(logind); break;
                case "exit":      applet = new ExitTray(logind); break;
            }
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

        // No monitors yet ⇒ one unpinned host window; hotplug rebuilds later.
        var mons = LumenCommon.Monitors.or_unpinned();
        for (int i = 0; i < mons.length; i++) {
            var mon = mons[i];
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
