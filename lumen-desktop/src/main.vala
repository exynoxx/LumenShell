// The window is created once at activate() and stays mapped for the lifetime
// of the process — there is no hide/show lifecycle, so no hold() and no
// command-line flag handling.
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

            if (!hotplug_wired) {
                var monitors = Gdk.Display.get_default().get_monitors();
                monitors.items_changed.connect((p, r, a) => rebuild_windows());
                hotplug_wired = true;
            }
        }
        for (int i = 0; i < wins.length; i++) wins.get(i).present();
    }

    // One drawer per monitor. The curtain/slide peek is per-output, so every
    // monitor needs its own grid surface for a peek on that output to reveal
    // anything (otherwise a peek on a monitor with no grid shows only the grey
    // backdrop). All drawers are independently focusable; the compositor routes
    // the keyboard to the grid on whichever output is active
    // (wayfire-curtain-peek on reveal, wayfire-default-focus thereafter).
    void build_windows() {
        var monitors = Gdk.Display.get_default().get_monitors();
        uint n = monitors.get_n_items();
        if (n == 0) {
            wins.add(new DesktopWindow(this, null));
            return;
        }
        for (uint i = 0; i < n; i++) {
            var mon = monitors.get_item(i) as Gdk.Monitor;
            wins.add(new DesktopWindow(this, mon));
        }
    }

    void rebuild_windows() {
        for (int i = 0; i < wins.length; i++) wins.get(i).destroy();
        wins = new GLib.GenericArray<DesktopWindow>();
        build_windows();
        for (int i = 0; i < wins.length; i++) wins.get(i).present();
    }
}

int main(string[] args) {
    var app = new DesktopApp();
    return app.run(args);
}
