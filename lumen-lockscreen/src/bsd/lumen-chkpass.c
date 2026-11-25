/*
 * lumen-chkpass — FreeBSD-only setuid-root password checker for
 * lumen-lockscreen.
 *
 * Why: OpenPAM's pam_unix verifies against master.passwd, which only root can
 * read (getpwnam() returns "*" as the hash to everyone else), and FreeBSD has
 * no unix_chkpwd. GTK refuses to run setuid, so the lock screen hands the
 * password to this tiny helper instead — the same arrangement as FreeBSD's
 * other screen lockers.
 *
 * Contract: no arguments; the password arrives on stdin (no terminator, read
 * to EOF); it only ever authenticates the *real* uid's own account against
 * the fixed "lumen-lockscreen" PAM service; the exit status is the PAM result
 * code (0 = PAM_SUCCESS). Failures are delayed so the helper can't be used to
 * brute-force the user's password quickly.
 */
#include <sys/param.h>
#include <sys/types.h>

#include <errno.h>
#include <pwd.h>
#include <security/pam_appl.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#define SERVICE       "lumen-lockscreen"
#define MAX_PASSWORD  1024
#define FAIL_DELAY_S  2

static char password[MAX_PASSWORD + 1];

static int conv(int num_msg, const struct pam_message **msg,
                struct pam_response **resp, void *appdata_ptr)
{
    (void) appdata_ptr;
    if (num_msg <= 0 || num_msg > PAM_MAX_NUM_MSG)
        return PAM_CONV_ERR;

    struct pam_response *r = calloc((size_t) num_msg, sizeof(*r));
    if (r == NULL)
        return PAM_BUF_ERR;

    for (int i = 0; i < num_msg; i++) {
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF ||
            msg[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            r[i].resp = strdup(password);
            if (r[i].resp == NULL) {
                for (int j = 0; j < i; j++) {
                    if (r[j].resp != NULL) {
                        explicit_bzero(r[j].resp, strlen(r[j].resp));
                        free(r[j].resp);
                    }
                }
                free(r);
                return PAM_BUF_ERR;
            }
        }
    }
    *resp = r;
    return PAM_SUCCESS;
}

int main(int argc, char **argv)
{
    (void) argv;
    closefrom(STDERR_FILENO + 1);
    if (argc != 1)
        return PAM_SYSTEM_ERR;

    struct passwd *pw = getpwuid(getuid());
    if (pw == NULL)
        return PAM_USER_UNKNOWN;
    char user[MAXLOGNAME];
    if (strlcpy(user, pw->pw_name, sizeof(user)) >= sizeof(user))
        return PAM_USER_UNKNOWN;

    size_t len = 0;
    while (len < MAX_PASSWORD) {
        ssize_t n = read(STDIN_FILENO, password + len, MAX_PASSWORD - len);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            break;
        len += (size_t) n;
    }
    password[len] = '\0';

    struct pam_conv pc = { conv, NULL };
    pam_handle_t *pamh = NULL;
    int rc = pam_start(SERVICE, user, &pc, &pamh);
    if (rc == PAM_SUCCESS)
        rc = pam_authenticate(pamh, PAM_SILENT);
    if (rc == PAM_SUCCESS)
        rc = pam_acct_mgmt(pamh, PAM_SILENT);
    if (pamh != NULL)
        pam_end(pamh, rc);

    explicit_bzero(password, sizeof(password));

    if (rc != PAM_SUCCESS)
        sleep(FAIL_DELAY_S);
    return rc > 255 ? PAM_SYSTEM_ERR : rc;
}
