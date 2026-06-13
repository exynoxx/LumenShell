// Always-on background app drawer. Unlike Kickoff, the window is created
// once at activate() and stays mapped for the lifetime of the process —
// there is no hide/show lifecycle, so no hold() and no command-line flag
// handling.
public class DesktopApp : Gtk.Application {

    private GLib.GenericArray<DesktopWindow> wins = new GLib.GenericArray<DesktopWindow>();
    private bool bound = false;
    private bool hotplug_wired = false;

    construct {
        application_id = "dev.lumen.desktop";
    }

    protected override void activate() {
        if (!bound) {
            // Bind foreign-toplevel before any window is shown so its
            // focus_changed handler sees the initial state on map.
            DesktopToplevels.instance.bind();
            bound = true;

            build_windows();

            // Start hidden behind a closed curtain. A no-op on a fresh session,
            // but if lumen-desktop restarted while peeked this hides the grid.
            LumenDesktop.CurtainIpc.close();

            if (read_multi_monitor() && !hotplug_wired) {
                var monitors = Gdk.Display.get_default().get_monitors();
                monitors.items_changed.connect((p, r, a) => rebuild_windows());
                hotplug_wired = true;
            }
        }
        for (int i = 0; i < wins.length; i++) wins.get(i).present();
    }

    // One drawer per monitor when enabled; the first monitor is the focus owner
    // (the only surface that grabs the keyboard — see DesktopWindow).
    void build_windows() {
        if (!read_multi_monitor()) {
            wins.add(new DesktopWindow(this, null, true));
            return;
        }
        var monitors = Gdk.Display.get_default().get_monitors();
        uint n = monitors.get_n_items();
        if (n == 0) {
            wins.add(new DesktopWindow(this, null, true));
            return;
        }
        for (uint i = 0; i < n; i++) {
            var mon = monitors.get_item(i) as Gdk.Monitor;
            wins.add(new DesktopWindow(this, mon, i == 0));
        }
    }

    void rebuild_windows() {
        for (int i = 0; i < wins.length; i++) wins.get(i).destroy();
        wins = new GLib.GenericArray<DesktopWindow>();
        build_windows();
        for (int i = 0; i < wins.length; i++) wins.get(i).present();
    }

    static bool read_multi_monitor() {
        var path = Environment.get_user_config_dir() + "/lumen-shell/desktop.ini";
        var kf = new GLib.KeyFile();
        try {
            kf.load_from_file(path, GLib.KeyFileFlags.NONE);
            return kf.get_boolean("desktop", "behavior.multi-monitor");
        } catch (Error e) {
            return false;
        }
    }
}

int main(string[] args) {
    var app = new DesktopApp();
    return app.run(args);
}
