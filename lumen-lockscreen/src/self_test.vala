using Gtk;

// LUMEN_LOCKSCREEN_SELF_TEST=1 (or --test): render the lock card in an ordinary
// decorated window — no ext-session-lock, no PAM, no real lock — so the UI can
// be iterated on a live session. Mirrors lumen-osd/src/self_test.vala.
//
// The fake auth accepts the password "test" and rejects everything else so the
// shake / error / backoff paths are exercisable by hand.
public class LockSelfTest : Object {

    private Gtk.Application app;

    public LockSelfTest(Gtk.Application app) {
        this.app = app;
    }

    public void run() {
        stderr.printf("[lumen-lockscreen] --test: rendering lock card (password \"test\" unlocks)\n");

        var user = AccountsClient.load_current_user();
        // PowerMenu needs a LogindBridge; in self-test the buttons are live but
        // harmless to leave unclicked.
        // No wlhooks/screencopy in self-test → null snapshot (theme image or
        // solid scrim backdrop). Exercises the card, not the live blur.
        var win = new LockWindow(app, true, user, new LogindBridge(), null);
        win.default_width = 1280;
        win.default_height = 800;
        win.decorated = true;
        win.title = "lumen-lockscreen (self-test)";

        if (win.password != null) {
            win.password.submitted.connect((pw) => {
                if (pw == "test") {
                    stderr.printf("[lumen-lockscreen] --test: correct, quitting\n");
                    app.quit();
                } else {
                    win.password.clear();
                    win.password.set_error("Incorrect password");
                    win.password.set_input_enabled(true);
                }
            });
        }

        win.present();
    }
}
