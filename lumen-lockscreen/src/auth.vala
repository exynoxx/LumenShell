// Invariant: the password buffer is never logged.
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
