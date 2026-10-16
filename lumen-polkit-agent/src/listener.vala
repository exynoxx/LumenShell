// libpolkit-agent-1 owns the DBus plumbing and the Session runs the PAM helper;
// the password is never stored, only handed to Session.response().
public class LumenAgentListener : PolkitAgent.Listener {

    private weak Gtk.Application app;

    public LumenAgentListener(Gtk.Application app) {
        this.app = app;
    }

    public override async bool initiate_authentication(
            string action_id,
            string message,
            string icon_name,
            Polkit.Details details,
            string cookie,
            GLib.List<Polkit.Identity> identities,
            GLib.Cancellable? cancellable) throws GLib.Error {

        GLib.debug("listener: initiate_authentication action=%s msg='%s' cookie=%s n_ids=%u",
                action_id, message, cookie, identities.length());
        var flow = new AuthFlow(app, message, icon_name, cookie,
                                identities, cancellable);
        var ok = yield flow.run();
        GLib.debug("listener: initiate_authentication returning %s", ok.to_string());
        return ok;
    }
}
