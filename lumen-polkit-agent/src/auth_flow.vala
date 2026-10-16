// A PolkitAgent.Session is single-use: each password attempt needs a fresh one.
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
        // A cancel emitted by tearing the window down after a SUCCESSFUL auth
        // must not flip the result to "dismissed".
        dialog.cancel.connect(() => {
            GLib.debug("flow: dialog.cancel signal (done=%s)", done.to_string());
            if (done) return;
            user_cancelled = true;
            finish(false);
        });
        dialog.identity_changed.connect((id) => { GLib.debug("flow: identity_changed"); chosen = id; restart_session(); });

        // polkitd's CancelAuthentication arrives as a cancel on this token.
        if (cancellable != null)
            cancellable.cancelled.connect(() => { GLib.debug("flow: cancellable.cancelled (polkitd CancelAuthentication)"); finish(false); });
    }

    // Current user, else root, else the first offered.
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
        GLib.debug("flow: run() begin");
        resume = run.callback;
        dialog.present();
        GLib.debug("flow: dialog.present() done");
        start_session();
        if (!done) { GLib.debug("flow: suspending (await user)"); yield; }
        GLib.debug("flow: resumed (done=%s gained=%s user_cancelled=%s)",
                done.to_string(), gained.to_string(), user_cancelled.to_string());

        // Decide the verdict BEFORE tearing the window down.
        bool cancelled = user_cancelled
            || (cancellable != null && cancellable.is_cancelled());

        dialog.dismiss();

        if (cancelled)
            throw new Polkit.Error.CANCELLED("authentication dismissed");
        return gained;
    }

    private void start_session() {
        GLib.debug("flow: start_session()");
        session = new PolkitAgent.Session(chosen, cookie);
        session.request.connect((req, echo) => { GLib.debug("session: request '%s' echo=%s", req, echo.to_string()); dialog.show_prompt(req, echo); });
        session.show_error.connect((t) => { GLib.debug("session: show_error '%s'", t); dialog.show_error_text(t); });
        session.show_info.connect((t) => { GLib.debug("session: show_info '%s'", t); dialog.show_info_text(t); });
        session.completed.connect(on_completed);
        session.initiate();
        GLib.debug("flow: session.initiate() returned");
    }

    private void restart_session() {
        if (session != null) { session.cancel(); session = null; }
        dialog.clear_password();
        start_session();
    }

    private void on_submit(string pw) {
        if (session == null || done) return;
        dialog.set_busy(true);
        session.response(pw);
    }

    private void on_completed(bool authorized) {
        GLib.debug("flow: on_completed authorized=%s done=%s", authorized.to_string(), done.to_string());
        if (done) return;
        if (authorized) { finish(true); return; }

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
        // A session that already completed (success) must not be cancelled.
        if (session != null && !authorized) session.cancel();
        session = null;
        if (resume != null) {
            var r = (owned) resume;
            r();
        }
    }
}
