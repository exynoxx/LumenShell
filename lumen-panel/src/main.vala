public delegate Lumen.TrayApplet AppletCtor ();

// A built-in applet in the tray.applet slot: label from LumenTray.CATALOG, a fresh
// instance per create() so one id can be realized on several panels.
class BuiltinApplet : GLib.Object, Lumen.TrayAppletFactory {
    string _label;
    AppletCtor ctor;

    public BuiltinApplet (string id, owned AppletCtor ctor) {
        _label = id;
        foreach (var info in LumenTray.CATALOG) if (info.id == id) _label = info.label;
        this.ctor = (owned) ctor;
    }

    public string label { owned get { return _label; } }
    public Lumen.TrayApplet create () { return ctor(); }
}

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
    PanelService panel_service;              // session-bus ToggleTray (global hotkey)
    SniWatcher sni_watcher;                  // SNI registry singleton, shared by every SysTray
    Lumen.Registry registry;                 // tray applets + presenter, built-in and extension
    ExtensionHost ext_host;
    LogindBridge logind;

    // One instance each, shared by every panel's applets — see activate().
    WifiService         wifi_service;
    BluetoothService    bluetooth_service;
    SoundService        sound_service;
    BatteryService      battery_service;
    PowerProfileService power_profile_service;
    BrightnessService   brightness_service;     // polls sysfs only while a slider is mapped

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
        brightness_service    = new BrightnessService();
        battery_service.ac_changed.connect(power_profile_service.refresh);

        var config = Lumen.ExtensionConfig.load(LumenCommon.Paths.extensions_json());
        registry = new Lumen.Registry(config);
        registry.declare(Lumen.SLOT_TRAY_APPLET, Lumen.Cardinality.MANY);
        registry.declare(Lumen.SLOT_TRAY_PRESENTER, Lumen.Cardinality.ONE);
        if (Environment.find_program_in_path("lumen-search") != null)
            builtin("search",    () => new SearchTray());
        builtin("systray",   () => new SysTray(sni_watcher));
        builtin("wifi",      () => new WifiTray(wifi_service));
        builtin("bluetooth", () => new BluetoothTray(bluetooth_service));
        builtin("battery",   () => new BatteryTray(battery_service, power_profile_service));
        builtin("sound",     () => new SoundTray(sound_service));
        builtin("clock",     () => new Clock(logind));
        builtin("exit",      () => new ExitTray(logind));
        registry.provide(Lumen.SLOT_TRAY_PRESENTER, "tray-classic",
                         new ClassicPresenter(logind, brightness_service));

        // Bind foreign-toplevel before building any AppBar so replay happens
        // synchronously when each AppBar subscribes inside its constructor.
        ToplevelStore.instance.bind();

        // The panel surface only gets keys once clicked, so the global tray hotkey
        // arrives over DBus from a Wayfire [command] binding.
        panel_service = new PanelService();
        panel_service.start();

        // Built-ins first so the panel never waits on valac; extensions rebuild once.
        build_windows();

        ext_host = new ExtensionHost(registry, config, app);
        ext_host.load_all.begin((obj, res) => {
            if (ext_host.load_all.end(res)) rebuild_windows();
        });

        if (PanelConfig.multi_monitor && !hotplug_wired) {
            var monitors = Gdk.Display.get_default().get_monitors();
            monitors.items_changed.connect((pos, removed, added) => rebuild_windows());
            hotplug_wired = true;
        }
    }

    void builtin (string id, owned AppletCtor ctor) {
        registry.provide(Lumen.SLOT_TRAY_APPLET, id, new BuiltinApplet(id, (owned) ctor));
    }

    // A fresh model per tray: a widget has one parent.
    Lumen.Tray? make_tray (Gtk.Window window) {
        var presenter = registry.active(Lumen.SLOT_TRAY_PRESENTER) as Lumen.TrayPresenter;
        if (presenter == null) return null;
        var ids = registry.provider_ids(Lumen.SLOT_TRAY_APPLET);
        var factories = registry.all(Lumen.SLOT_TRAY_APPLET);
        var model = new Lumen.TrayModel();
        foreach (var id in PanelConfig.tray_enabled_order(ids)) {
            for (int i = 0; i < ids.length; i++) {
                if (ids[i] != id) continue;
                model.add(((Lumen.TrayAppletFactory) factories[i]).create());
                break;
            }
        }
        return presenter.create(model, window);
    }

    // The first monitor is the tray host; single-monitor mode builds one window
    // with monitor = null.
    void build_windows () {
        build_windows_on_monitors();
        panel_service.tray = windows.length > 0 ? windows[0].tray : null;
    }

    void build_windows_on_monitors () {
        if (!PanelConfig.multi_monitor) {
            windows.add(new PanelWindow(app, null, true, make_tray));
            return;
        }

        var monitors = Gdk.Display.get_default().get_monitors();
        uint n = monitors.get_n_items();
        if (n == 0) {
            // No monitors reported (yet) — fall back to one unpinned window so
            // the panel still appears; hotplug will rebuild when outputs arrive.
            windows.add(new PanelWindow(app, null, true, make_tray));
            return;
        }
        for (uint i = 0; i < n; i++) {
            var mon = monitors.get_item(i) as Gdk.Monitor;
            bool host = (i == 0);
            if (host || PanelConfig.tray_all_monitors)
                windows.add(new PanelWindow(app, mon, host, make_tray));
            else
                windows.add(new PanelWindow(app, mon, host, null));
        }
    }

    // Every window gets fresh trays (the SNI watcher and services live here, not in them).
    void rebuild_windows () {
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
