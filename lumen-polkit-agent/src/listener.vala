// LumenAgentListener — our PolkitAgent.Listener subclass.
//
// libpolkit-agent-1 owns all the DBus plumbing: it exports the
// org.freedesktop.PolicyKit1.AuthenticationAgent interface, handles
// RegisterAuthenticationAgent for us (via Listener.register), and translates an
// incoming BeginAuthentication into a call to initiate_authentication() below
// (and CancelAuthentication into cancelling the GLib.Cancellable). All we add is
// the UI: drive an AuthDialog through a PolkitAgent.Session, which itself runs
// the setuid polkit-agent-helper-1 / PAM conversation and reports the verdict
// back to polkitd. We never see, store, or transmit the password ourselves
// beyond handing each typed response to Session.response().
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

        lpa_dbg("listener: initiate_authentication action=%s msg='%s' cookie=%s n_ids=%u",
                action_id, message, cookie, identities.length());
        var flow = new AuthFlow(app, message, icon_name, cookie,
                                identities, cancellable);
        var ok = yield flow.run();
        lpa_dbg("listener: initiate_authentication returning %s", ok.to_string());
        return ok;
    }
}
