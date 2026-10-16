using LumenCommon;

public class LockApp : Gtk.Application {

    private LockManager manager;
    private LockService service;
    private bool activated = false;

    public LockApp() {
        Object(
            application_id: "org.lumenshell.LockApp",
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    protected override void activate() {
        if (activated) return;
        activated = true;

        DiagLog.log("activate: session-lock-supported=%s",
            GtkSessionLock.is_supported().to_string());

        Theme.load();
        install_root_css();

        manager = new LockManager(this);
        service = new LockService(manager);
        own_bus_name();
        hold();
    }

    private void own_bus_name() {
        Bus.own_name(
            BusType.SESSION,
            "org.lumenshell.Lock",
            BusNameOwnerFlags.NONE,
            (conn) => {
                try {
                    conn.register_object("/org/lumenshell/Lock", service);
                    DiagLog.log("bus: acquired org.lumenshell.Lock, object registered");
                } catch (IOError e) {
                    warning("lumen-lockscreen: register_object failed: %s", e.message);
                }
            },
            () => { },
            () => {
                warning("lumen-lockscreen: could not acquire org.lumenshell.Lock (already running?); exiting");
                quit();
            }
        );
    }

    private void install_root_css() {
        var provider = new Gtk.CssProvider();
        try {
            var bytes = resources_lookup_data(
                "/org/lumenshell/lockscreen/res/style.css", ResourceLookupFlags.NONE);
            var combined = Theme.generate_root_css() + "\n" + (string) bytes.get_data();
            provider.load_from_string(combined);
        } catch (Error e) {
            warning("lumen-lockscreen: failed to load CSS: %s", e.message);
            return;
        }
        Gtk.StyleContext.add_provider_for_display(
            (!) Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }
}

public static int main(string[] args) {
    // Before any GTK/GLib work: the daemon is invisible until it locks, so the
    // breadcrumb trail is the only evidence of a startup failure.
    DiagLog.install("lumen-lockscreen");

    return new LockApp().run(args);
}
