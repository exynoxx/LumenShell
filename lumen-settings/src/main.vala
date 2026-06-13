using Gtk;

namespace LumenSettings {

    public class SettingsApp : Gtk.Application {
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
            registry.add(new DisplayPage(),       "LumenShell");
            registry.add(new PanelPage(),         "LumenShell");
            registry.add(new DesktopPage(),       "LumenShell");
            registry.add(new PowerPage(),         "LumenShell");
            registry.add(new OsdPage(),           "LumenShell");
            registry.add(new NotificationsPage(), "LumenShell");
#if WITH_WAYFIRE_CONFIG
            Wayfire.WayfirePages.register(registry);
#endif
            registry.add(new AboutPage(), "About");
        }
    }

    public static int main(string[] args) {
        DiagLog.install();
        var app = new SettingsApp();
        return app.run(args);
    }
}
