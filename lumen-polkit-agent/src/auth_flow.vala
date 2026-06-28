// AuthFlow — one authentication request, start to finish.
//
// Bridges an AuthDialog (the UI) to a PolkitAgent.Session (the PAM driver) and
// suspends the listener's async initiate_authentication() until the user either
// authenticates, cancels, or runs out of attempts.
//
// A PolkitAgent.Session is single-use: each password attempt needs a fresh one.
// So on a failed attempt we tear the session down and start_session() again,
// keeping the same dialog open (Apple/GNOME "Sorry, try again." behaviour).
public class AuthFlow : GLib.Object {

    private const int MAX_ATTEMPTS = 3;

    private weak Gtk.Application app;
    private string             cookie;
    private Polkit.Identity[]  ids;
    private Polkit.Identity    chosen;
    private AuthDialog         dialog;
    private GLib.Cancellable?  cancellable;

    private PolkitAgent.Session? session = null;
    private bool         gained        = false;
    private bool         user_cancelled = false;
    private bool         done          = false;
    private int          attempts      = 0;
    private SourceFunc?  resume        = null;

    public AuthFlow(Gtk.Application app, string message, string icon_name,
                    string cookie, GLib.List<Polkit.Identity> identities,
                    GLib.Cancellable? cancellable) {
        this.app         = app;
        this.cookie      = cookie;
        this.cancellable = cancellable;

        var arr = new Polkit.Identity[0];
        foreach (var id in identities) arr += id;
        this.ids    = arr;
        this.chosen = pick_default(arr);

        dialog = new AuthDialog(app, message, icon_name, identities, chosen);
        dialog.submit.connect(on_submit);
        // Only count a cancel that arrives while the flow is still live. A
        // cancel emitted as a side effect of tearing the window down after a
        // SUCCESSFUL auth must not flip the result to "dismissed".
        dialog.cancel.connect(() => {
            lpa_dbg("flow: dialog.cancel signal (done=%s)", done.to_string());
            if (done) return;
            user_cancelled = true;
            finish(false);
        });
        dialog.identity_changed.connect((id) => { lpa_dbg("flow: identity_changed"); chosen = id; restart_session(); });

        // polkitd's CancelAuthentication arrives as a cancel on this token.
        if (cancellable != null)
            cancellable.cancelled.connect(() => { lpa_dbg("flow: cancellable.cancelled (polkitd CancelAuthentication)"); finish(false); });
    }

    // Prefer authenticating as the current user when polkit offers that
    // identity; otherwise prefer root; otherwise just take the first offered.
    private static Polkit.Identity pick_default(Polkit.Identity[] ids) {
        int my = (int) Posix.getuid();
        Polkit.Identity? root = null;
        foreach (var id in ids) {
            if (id is Polkit.UnixUser) {
                var uu = (Polkit.UnixUser) id;
                if (uu.get_uid() == my)  return id;
                if (uu.get_uid() == 0)   root = id;
            }
        }
        if (root != null) return root;
        return ids[0];
    }

    public async bool run() throws GLib.Error {
        lpa_dbg("flow: run() begin");
        resume = run.callback;
        dialog.present();
        lpa_dbg("flow: dialog.present() done");
        start_session();
        if (!done) { lpa_dbg("flow: suspending (await user)"); yield; }
        lpa_dbg("flow: resumed (done=%s gained=%s user_cancelled=%s)",
                done.to_string(), gained.to_string(), user_cancelled.to_string());

        // Decide the verdict BEFORE tearing the window down — dismiss() must not
        // be able to influence it (it won't re-emit cancel, but be explicit).
        bool cancelled = user_cancelled
            || (cancellable != null && cancellable.is_cancelled());

        dialog.dismiss();

        if (cancelled)
            throw new Polkit.Error.CANCELLED("authentication dismissed");
        return gained;
    }

    private void start_session() {
        lpa_dbg("flow: start_session()");
        session = new PolkitAgent.Session(chosen, cookie);
        session.request.connect((req, echo) => { lpa_dbg("session: request '%s' echo=%s", req, echo.to_string()); dialog.show_prompt(req, echo); });
        session.show_error.connect((t) => { lpa_dbg("session: show_error '%s'", t); dialog.show_error_text(t); });
        session.show_info.connect((t) => { lpa_dbg("session: show_info '%s'", t); dialog.show_info_text(t); });
        session.completed.connect(on_completed);
        session.initiate();
        lpa_dbg("flow: session.initiate() returned");
    }

    private void restart_session() {
        if (session != null) { session.cancel(); session = null; }
        dialog.clear_password();
        start_session();
    }

    private void on_submit(string pw) {
        lpa_dbg("flow: on_submit (len=%d, session=%s, done=%s)", pw.length, (session != null).to_string(), done.to_string());
        if (session == null || done) return;
        dialog.set_busy(true);
        session.response(pw);
    }

    private void on_completed(bool authorized) {
        lpa_dbg("flow: on_completed authorized=%s done=%s", authorized.to_string(), done.to_string());
        if (done) return;
        if (authorized) { finish(true); return; }

        // Wrong password / PAM denial. Offer a retry with a fresh session until
        // the attempt budget is spent.
        session = null;
        attempts++;
        dialog.set_busy(false);
        if (attempts >= MAX_ATTEMPTS) {
            dialog.show_error_text("Authentication failed.");
            finish(false);
            return;
        }
        dialog.show_error_text("Sorry, try again.");
        dialog.clear_password();
        start_session();
    }

    private void finish(bool authorized) {
        if (done) return;
        done   = true;
        gained = authorized;
        // Only cancel a still-running session; a session that already completed
        // (success path) must not be cancelled.
        if (session != null && !authorized) session.cancel();
        session = null;
        if (resume != null) {
            var r = (owned) resume;
            r();
        }
    }
}
