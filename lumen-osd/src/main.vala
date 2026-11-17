public class OsdApp : Gtk.Application {

    private OsdWindowGroup group;
    private OsdService     service;
    private StateWatcher watcher;
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
        LumenCommon.Css.install(Theme.generate_root_css());
        group = new OsdWindowGroup(this);

        service = new OsdService(group);
        watcher = new StateWatcher(service);
        own_bus_name();
        hold();
    }

    private void own_bus_name() {
        Bus.own_name(
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
}

public static int main(string[] args) {
    return new OsdApp().run(args);
}
