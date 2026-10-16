using Gtk;

public class OsdApp : Gtk.Application {

    private OsdWindowGroup group;
    private OsdService     service;
    private StateWatcher watcher;
    private uint         owner_id = 0;
    private bool         activated = false;

    public OsdApp() {
        Object(
            application_id: "org.lumenshell.OSDApp",
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    protected override void activate() {
        if (!GtkLayerShell.is_supported()) {
            stderr.printf("lumen-osd: gtk4-layer-shell is not supported by this compositor\n");
            quit();
            return;
        }
        if (activated) return;
        activated = true;

        Theme.load();
        install_root_css();
        group = new OsdWindowGroup(this);

        service = new OsdService(group);
        watcher = new StateWatcher(service);
        own_bus_name();
        hold();
    }

    private void own_bus_name() {
        owner_id = Bus.own_name(
            BusType.SESSION,
            "org.lumenshell.OSD",
            BusNameOwnerFlags.NONE,
            (conn) => {
                try {
                    conn.register_object("/org/lumenshell/OSD", service);
                } catch (IOError e) {
                    stderr.printf("lumen-osd: register_object failed: %s\n", e.message);
                }
            },
            () => { },
            () => {
                stderr.printf("lumen-osd: could not acquire org.lumenshell.OSD (already running?)\n");
                quit();
            }
        );
    }

    private void install_root_css() {
        var provider = new Gtk.CssProvider();
        provider.load_from_string(Theme.generate_root_css());
        Gtk.StyleContext.add_provider_for_display(
            (!) Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }
}

public static int main(string[] args) {
    return new OsdApp().run(args);
}
