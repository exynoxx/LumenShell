// Always-on background app drawer. Unlike Kickoff, the window is created
// once at activate() and stays mapped for the lifetime of the process —
// there is no hide/show lifecycle, so no hold() and no command-line flag
// handling.
public class DesktopApp : Gtk.Application {

    private DesktopWindow? win = null;

    construct {
        application_id = "dev.lumen.desktop";
    }

    protected override void activate() {
        if (win == null) {
            win = new DesktopWindow(this);
        }
        win.present();
    }
}

int main(string[] args) {
    var app = new DesktopApp();
    return app.run(args);
}
