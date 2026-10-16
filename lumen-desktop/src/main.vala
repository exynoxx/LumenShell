namespace LumenDesktop {

    public class DesktopApp : Gtk.Application {

        private GLib.GenericArray<DesktopWindow> wins
            = new GLib.GenericArray<DesktopWindow>();
        private bool started = false;
        private bool removing = false;

        construct {
            application_id = "org.lumenshell.Desktop";
        }

        protected override void activate() {
            if (!started) {
                started = true;

                WidgetRegistry.register_builtins();
                DesktopConfig.load();

                build_windows();

                var monitors = Gdk.Display.get_default().get_monitors();
                monitors.items_changed.connect((p, r, a) => rebuild_windows());
            }
            for (int i = 0; i < wins.length; i++) wins.get(i).present();
        }

        // Each window builds its own widget instances (a Gtk.Widget has one
        // parent), so per-monitor browse state stays independent.
        private void build_windows() {
            var monitors = Gdk.Display.get_default().get_monitors();
            uint n = monitors.get_n_items();
            if (n == 0) {
                add_window_for(null);
                return;
            }
            for (uint i = 0; i < n; i++) {
                var mon = monitors.get_item(i) as Gdk.Monitor;
                add_window_for(mon);
            }
        }

        private void add_window_for(Gdk.Monitor? monitor) {
            var win = new DesktopWindow(this, monitor, DesktopConfig.widgets);
            win.widget_removed.connect(remove_widget);
            wins.add(win);
        }

        // Full reload + rebuild so every monitor drops it; deferred to idle
        // because the emitting window is about to be destroyed.
        private void remove_widget(WidgetSpec spec) {
            if (removing) return;
            removing = true;

            DesktopConfig.remove_widget(spec);
            GLib.Idle.add(() => {
                DesktopConfig.load();
                rebuild_windows();
                removing = false;
                return GLib.Source.REMOVE;
            });
        }

        private void rebuild_windows() {
            for (int i = 0; i < wins.length; i++) wins.get(i).destroy();
            wins = new GLib.GenericArray<DesktopWindow>();
            build_windows();
            for (int i = 0; i < wins.length; i++) wins.get(i).present();
        }
    }
}

int main(string[] args) {
    var app = new LumenDesktop.DesktopApp();
    return app.run(args);
}
