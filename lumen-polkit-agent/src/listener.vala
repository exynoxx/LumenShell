// libpolkit-agent-1 owns the DBus plumbing and the Session runs the PAM helper;
// the password is never stored, only handed to Session.response().
public class LumenAgentListener : PolkitAgent.Listener {

    public override async bool initiate_authentication(
            string action_id,
            string message,
            string icon_name,
            Polkit.Details details,
            string cookie,
            GLib.List<Polkit.Identity> identities,
            GLib.Cancellable? cancellable) throws GLib.Error {

        GLib.debug("listener: initiate_authentication action=%s msg='%s' n_ids=%u",
                action_id, message, identities.length());
        var flow = new AuthFlow(message, icon_name, cookie,
                                identities, cancellable);
        var ok = yield flow.run();
        GLib.debug("listener: initiate_authentication returning %s", ok.to_string());
        return ok;
    }
}
