using Gtk;

public class OsdApp : Gtk.Application {

    private OsdWindow?         window  = null;
    private OsdService?        service = null;
    private BrightnessWatcher? watcher = null;
    private uint               owner_id = 0;
    public  bool               test_mode = false;

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
        watcher = new BrightnessWatcher((!) service);
        own_bus_name();

        // Keep the application alive even with no visible window.
        hold();

        if (test_mode) run_self_test();
    }

    private struct TestFrame {
        bool   is_chip;
        string icon;
        double value;
        string text;
    }

    private void run_self_test() {
        stderr.printf("[lumen-osd] --test: running development visualizer\n");
        var w = (!) window;
        var p = w.pill;

        // Cover every kind, every icon variant the daemon emits, and both
        // pill modes (slider with bar + value, chip with icon + text).
        TestFrame[] frames = {
            // ---- output volume: muted / low / medium / high ----
            { false, "audio-volume-muted-symbolic",        0.00, "Volume muted" },
            { false, "audio-volume-low-symbolic",          0.20, "Volume 20%" },
            { false, "audio-volume-medium-symbolic",       0.55, "Volume 55%" },
            { false, "audio-volume-high-symbolic",         0.95, "Volume 95%" },

            // ---- mic: muted / low / medium / high ----
            { false, "microphone-sensitivity-muted-symbolic",  0.00, "Mic muted" },
            { false, "microphone-sensitivity-low-symbolic",    0.20, "Mic 20%" },
            { false, "microphone-sensitivity-medium-symbolic", 0.55, "Mic 55%" },
            { false, "microphone-sensitivity-high-symbolic",   0.90, "Mic 90%" },

            // ---- screen brightness: low / med / max ----
            { false, "display-brightness-symbolic",        0.10, "Brightness 10%" },
            { false, "display-brightness-symbolic",        0.50, "Brightness 50%" },
            { false, "display-brightness-symbolic",        1.00, "Brightness 100%" },

            // ---- keyboard brightness: off / mid / max ----
            { false, "keyboard-brightness-symbolic",       0.00, "Kbd light off" },
            { false, "keyboard-brightness-symbolic",       0.50, "Kbd light 50%" },
            { false, "keyboard-brightness-symbolic",       1.00, "Kbd light 100%" },

            // ---- caps lock chip (both states) ----
            { true,  "keyboard-symbolic",                  0.00, "Caps ON" },
            { true,  "keyboard-symbolic",                  0.00, "Caps OFF" },

            // ---- custom: chip variant and slider variant ----
            { true,  "dialog-information-symbolic",        0.00, "Hello chip" },
            { false, "dialog-information-symbolic",        0.40, "Custom 40%" }
        };

        int step = 0;
        Timeout.add(900, () => {
            if (step >= frames.length) {
                stderr.printf("[lumen-osd] --test: done, quitting\n");
                w.set_visible(false);
                quit();
                return Source.REMOVE;
            }
            var f = frames[step];
            stderr.printf("[lumen-osd] --test [%2d/%d] %s icon=%s value=%.2f text=\"%s\"\n",
                          step + 1, frames.length,
                          f.is_chip ? "chip  " : "slider",
                          f.icon, f.value, f.text);
            if (f.is_chip) {
                p.show_chip(f.icon, f.text);
            } else {
                p.show_slider(f.icon, f.value, f.text);
            }
            w.set_visible(true);
            step++;
            return Source.CONTINUE;
        });
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
    var app = new OsdApp();
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
