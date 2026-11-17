using LumenCommon;

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

            Theme.install();
            // Sidebar icons ship in the gresource so the user's icon theme can't swap or drop them.
            Gtk.IconTheme.get_for_display(Gdk.Display.get_default())
                .add_resource_path("/org/lumenshell/settings/icons");
            register_pages();

            window = new SettingsWindow(this, registry);
            window.present();
        }

        void register_pages() {
            registry.add(new WallpaperPage(),     "LumenShell");
            registry.add(new PanelPage(),         "LumenShell");
            registry.add(new DrawerPage(),        "LumenShell");
            registry.add(new PowerPage(),         "LumenShell");
            registry.add(new OsdPage(),           "LumenShell");
            registry.add(new NotificationsPage(), "LumenShell");
            registry.add(new LockscreenPage(),    "LumenShell");
            registry.add(new SearchPage(),        "LumenShell");
            registry.add(new UsersPage(),         "LumenShell");
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
