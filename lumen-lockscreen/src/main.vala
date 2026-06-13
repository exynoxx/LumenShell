using Gtk;

// LockApp — long-running, invisible-until-locked daemon. Owns org.lumenshell.Lock
// and the LockManager. Realize-hidden idiom from lumen-osd: no window exists
// until a trigger calls LockManager.lock_now(), which creates the lock surfaces.
public class LockApp : Gtk.Application {

    private LockManager manager;
    private LockService service;
    private uint owner_id = 0;
    private bool activated = false;
    public  bool test_mode = false;

    public LockApp() {
        Object(
            application_id: "org.lumenshell.LockApp",
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    protected override void activate() {
        if (activated) return;
        activated = true;

        Theme.load();
        install_root_css();

        if (test_mode) {
            new LockSelfTest(this).run();
            hold();
            return;
        }

        manager = new LockManager(this);
        service = new LockService(manager);
        own_bus_name();

        // No visible window until something locks. Keep the app alive anyway.
        hold();
    }

    private void own_bus_name() {
        owner_id = Bus.own_name(
            BusType.SESSION,
            "org.lumenshell.Lock",
            BusNameOwnerFlags.NONE,
            (conn) => {
                try {
                    conn.register_object("/org/lumenshell/Lock", service);
                } catch (IOError e) {
                    stderr.printf("lumen-lockscreen: register_object failed: %s\n", e.message);
                }
            },
            () => { },
            () => {
                stderr.printf("lumen-lockscreen: could not acquire org.lumenshell.Lock (already running?)\n");
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
            stderr.printf("lumen-lockscreen: failed to load CSS: %s\n", e.message);
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
    var app = new LockApp();
    if (Environment.get_variable("LUMEN_LOCKSCREEN_SELF_TEST") == "1")
        app.test_mode = true;

    string[] gtk_args = { args[0] };
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--test") {
            app.test_mode = true;
        } else {
            gtk_args += args[i];
        }
    }
    return app.run(gtk_args);
}
