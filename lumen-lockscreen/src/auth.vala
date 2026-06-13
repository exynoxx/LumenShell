using GLib;

// PamAuth — runs the blocking PAM stack off the main thread and delivers the
// verdict back on the main loop (so the compositor keeps getting frame/ping
// events while the user's password is verified). Wraps the C helper in
// pam_auth.c via the PamHelper binding.
//
// Invariant (AGENTS.md): the password buffer is never logged.
public class PamAuth : GLib.Object {

    public delegate void ResultFunc(bool ok);

    private string service;
    private string user;

    public PamAuth(string service) {
        this.service = service;
        this.user = Environment.get_user_name();
    }

    public void authenticate_async(string password, owned ResultFunc cb) {
        // Copy primitives into the worker closure; never reference live UI.
        string svc = service;
        string usr = user;
        string pw  = password;

        new Thread<void>("lumen-pam", () => {
            int rc = PamHelper.authenticate(svc, usr, pw);
            bool ok = (rc == 0);   // PAM_SUCCESS == 0
            // Hop back to the main loop to touch GTK.
            Idle.add(() => {
                cb(ok);
                return Source.REMOVE;
            });
        });
    }
}
