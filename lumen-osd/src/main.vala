using Gtk;

public class OsdApp : Gtk.Application {

    private OsdWindow?  window  = null;
    private OsdService? service = null;
    private uint        owner_id = 0;

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

        if (window != null) return;

        Theme.load();
        window = new OsdWindow(this);
        install_root_css();
        // Realize but stay hidden until a Show request arrives.
        window.present();
        window.set_visible(false);

        service = new OsdService((!) window);
        own_bus_name();

        // Keep the application alive even with no visible window.
        hold();
    }

    private void own_bus_name() {
        owner_id = Bus.own_name(
            BusType.SESSION,
            "org.lumenshell.OSD",
            BusNameOwnerFlags.NONE,
            (conn) => {
                try {
                    conn.register_object("/org/lumenshell/OSD", (!) service);
                } catch (IOError e) {
                    stderr.printf("lumen-osd: register_object failed: %s\n", e.message);
                }
            },
            () => { /* name acquired */ },
            () => {
                stderr.printf("lumen-osd: could not acquire org.lumenshell.OSD (already running?)\n");
                quit();
            }
        );
    }

    private void install_root_css() {
        var provider = new Gtk.CssProvider();
        provider.load_from_string(
            ".lumen-osd-root { background-color: transparent; }" +
            ".lumen-osd-root label { color: %s; }".printf(rgba_css(Theme.text))
        );
        Gtk.StyleContext.add_provider_for_display(
            (!) Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    private static string rgba_css(Gdk.RGBA c) {
        // Gdk.RGBA.to_string() emits a locale-independent rgb()/rgba() string.
        return c.to_string();
    }
}

public static int main(string[] args) {
    return new OsdApp().run(args);
}
