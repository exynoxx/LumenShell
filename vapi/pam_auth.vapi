/* Binding for the in-tree PAM helper (lumen-lockscreen/src/pam_auth.c).
 * One blocking call; the Vala side runs it on a worker thread. */
[CCode(cheader_filename = "pam_auth.h")]
namespace PamHelper {
    [CCode(cname = "lumen_pam_authenticate")]
    public int authenticate(string service, string user, string password);
}
