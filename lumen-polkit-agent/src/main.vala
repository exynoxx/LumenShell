using Gtk;

// lumen-polkit-agent — the LumenShell PolicyKit authentication agent.
//
// PolicyKit (polkitd) only prompts the user for a password when an
// *authentication agent* is registered for the active session. A bare Wayfire
// session has none, so every privileged action (mounting disks, installing
// packages, `pkexec foo`, NetworkManager system connections, …) silently
// fails with "not authorized". This daemon fills that gap: it registers a
// PolkitAgent.Listener for our login session and pops a password dialog
// whenever polkitd asks for authentication.
//
// It is also what makes lumen-desktop's "Ctrl+click → run as administrator"
// work: that path shells out to `pkexec`, whose org.freedesktop.policykit.exec
// action routes straight through this agent.
//
// Realize-hidden idiom (same as lumen-osd / lumen-lockscreen): no window exists
// until polkitd calls BeginAuthentication; the AuthFlow builds an AuthDialog on
// demand. Must run as a child of the Wayfire session (Wayfire [autostart]) so
// the session it registers for is the one the user is sitting in front of.
namespace LumenPolkitAgent {

public class App : Gtk.Application {

    private LumenAgentListener? listener = null;
    private void* reg_handle = null;
    private bool activated = false;
    public  bool test_mode = false;

    public App() {
        Object(application_id: "org.lumenshell.PolkitAgent",
               flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void activate() {
        if (activated) return;
        activated = true;

        install_css();

        if (test_mode) {
            run_self_test();
            hold();
            return;
        }

        if (!register_agent()) {
            // Another agent already owns this session (a full DE was started
            // alongside us), or polkit is unavailable. Nothing useful to do —
            // exit rather than linger as a dead process that never prompts.
            quit();
            return;
        }
        hold();
    }

    private bool register_agent() {
        try {
            // The subject is *this* process's login session; polkitd will only
            // call us for authentications originating in the same session.
            var subject = new Polkit.UnixSession.for_process_sync(
                (int) Posix.getpid(), null);
            if (subject == null) {
                warning("lumen-polkit-agent: cannot resolve this process's "
                        + "login session (not under logind?)");
                return false;
            }

            listener = new LumenAgentListener(this);
            reg_handle = listener.register(
                PolkitAgent.RegisterFlags.NONE,
                subject,
                "/org/lumenshell/PolkitAgent/AuthenticationAgent",
                null);
            message("lumen-polkit-agent: registered as the session "
                    + "authentication agent");
            return true;
        } catch (Error e) {
            warning("lumen-polkit-agent: registration failed (is another "
                    + "authentication agent already running?): %s", e.message);
            return false;
        }
    }

    public override void shutdown() {
        if (reg_handle != null) {
            PolkitAgent.Listener.unregister(reg_handle);
            reg_handle = null;
        }
        base.shutdown();
    }

    // --test / LUMEN_POLKIT_AGENT_SELF_TEST: pop the dialog with a dummy flow so
    // the UI can be eyeballed without polkitd. No PAM, no real authorization.
    private void run_self_test() {
        var ids = new GLib.List<Polkit.Identity>();
        try { ids.append(new Polkit.UnixUser.for_name(Environment.get_user_name())); }
        catch (Error e) { /* ignore — empty selector is fine for a smoke test */ }

        var dlg = new AuthDialog(this,
            "Authentication is required to run a program as administrator "
            + "(self-test).",
            "dialog-password", ids, ids.nth_data(0));
        dlg.show_prompt("Password:", false);
        dlg.submit.connect((pw) => {
            stdout.printf("self-test: submitted a password of length %d\n",
                          pw.length);
            dlg.set_busy(false);
            dlg.show_error_text("Self-test mode — not actually authenticating.");
        });
        dlg.cancel.connect(() => dlg.close());
        dlg.present();
    }

    private void install_css() {
        var p = new Gtk.CssProvider();
        p.load_from_string(AGENT_CSS);
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}

public static int main(string[] args) {
    var app = new App();
    if (Environment.get_variable("LUMEN_POLKIT_AGENT_SELF_TEST") == "1")
        app.test_mode = true;

    // Strip our own flags before handing argv to GApplication, which would
    // otherwise reject --test as an unknown option (same idiom as lumen-lockscreen).
    string[] gtk_args = { args[0] };
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--test") app.test_mode = true;
        else gtk_args += args[i];
    }
    return app.run(gtk_args);
}

}
