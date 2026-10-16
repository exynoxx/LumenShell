// Must run inside the Wayfire session so it registers for the session the user
// is sitting in front of.
namespace LumenPolkitAgent {

public class App : Gtk.Application {

    private LumenAgentListener? listener = null;
    private void* reg_handle = null;
    private bool activated = false;

    public App() {
        Object(application_id: "org.lumenshell.PolkitAgent",
               flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void activate() {
        if (activated) return;
        activated = true;

        install_css();

        if (!register_agent()) {
            // Another agent owns this session, or no polkit: exit, don't linger.
            quit();
            return;
        }
        hold();
    }

    private bool register_agent() {
        try {
            // polkitd only calls us for authentications from this session.
            var subject = new Polkit.UnixSession.for_process_sync(
                (int) Posix.getpid(), null);
            if (subject == null) {
                warning("lumen-polkit-agent: cannot resolve this process's "
                        + "login session (not under logind?)");
                return false;
            }

            listener = new LumenAgentListener();
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

    private void install_css() {
        var p = new Gtk.CssProvider();
        p.load_from_string(AGENT_CSS);
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}

public static int main(string[] args) {
    return new App().run(args);
}

}
