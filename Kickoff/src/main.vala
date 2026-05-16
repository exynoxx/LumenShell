// Single-instance daemon. The first invocation creates the (hidden) window
// and holds the app alive; subsequent `kickoff --show` runs are routed to
// the primary instance and just unhide the existing window with a fresh
// intro animation.
public class KickoffApp : Gtk.Application {

    private KickoffWindow? win = null;

    construct {
        application_id = "dev.lumen.kickoff";
        flags = GLib.ApplicationFlags.HANDLES_COMMAND_LINE;
    }

    protected override void activate() {
        ensure_window();
        win.show_with_intro();
    }

    public override int command_line(ApplicationCommandLine cl) {
        bool want_show = false;
        bool want_daemon = false;
        var argv = cl.get_arguments();
        for (int i = 1; i < argv.length; i++) {
            switch (argv[i]) {
                case "--show":   want_show = true;   break;
                case "--daemon": want_daemon = true; break;
            }
        }
        // Default action (no flags) shows, so plain `kickoff` still works.
        if (!want_show && !want_daemon) want_show = true;

        ensure_window();
        if (want_show) win.show_with_intro();
        return 0;
    }

    private void ensure_window() {
        if (win != null) return;
        win = new KickoffWindow(this);
        // hold() keeps the app alive across window-hides — otherwise GTK
        // would quit when the last visible window goes away.
        hold();
    }
}

int main(string[] args) {
    var app = new KickoffApp();
    return app.run(args);
}
