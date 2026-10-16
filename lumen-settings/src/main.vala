using LumenCommon;
using Gtk;

namespace LumenSettings {

    public class SettingsApp : Adw.Application {
        SettingsWindow window;
        public PageRegistry registry;

        public SettingsApp() {
            Object(
                application_id: "org.lumenshell.Settings",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
            registry = new PageRegistry();
        }

        protected override void activate() {
            if (window != null) {
                window.present();
                return;
            }

            // The bundled palette is dark-only; force libadwaita to match.
            Adw.StyleManager.get_default().color_scheme = Adw.ColorScheme.FORCE_DARK;

            Theme.load();
            install_css();
            register_pages();

            window = new SettingsWindow(this, registry);
            window.present();
        }

        void install_css() {
            var provider = new Gtk.CssProvider();
            try {
                var bytes = resources_lookup_data(
                    "/org/lumenshell/settings/res/style.css",
                    ResourceLookupFlags.NONE);
                var base_css = (string) bytes.get_data();
                var combined = Theme.generate_root_css() + "\n" + base_css;
                provider.load_from_string(combined);
            } catch (Error e) {
                stderr.printf("lumen-settings: failed to load CSS: %s\n", e.message);
                return;
            }
            Gtk.StyleContext.add_provider_for_display(
                (!) Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        void register_pages() {
            registry.add(new WallpaperPage(),     "LumenShell");
            registry.add(new PanelPage(),         "LumenShell");
            registry.add(new DrawerPage(),        "LumenShell");
            registry.add(new PowerPage(),         "LumenShell");
            registry.add(new OsdPage(),           "LumenShell");
            registry.add(new NotificationsPage(), "LumenShell");
            registry.add(new LockscreenPage(),    "LumenShell");
            registry.add(new DisplayPage(),       "Input");
            registry.add(new KeyboardPage(),      "Input");
            registry.add(new MousePage(),         "Input");
            registry.add(new TouchpadPage(),      "Input");
            registry.add(new NetworkingPage(),    "Network");
            registry.add(new SoundPage(),         "Network");
#if WITH_WAYFIRE_CONFIG
            Wayfire.WayfirePages.register(registry);
#endif
            registry.add(new AboutPage(), "About");
        }
    }

    public static int main(string[] args) {
        DiagLog.install("lumen-settings");
        var app = new SettingsApp();
        return app.run(args);
    }
}
