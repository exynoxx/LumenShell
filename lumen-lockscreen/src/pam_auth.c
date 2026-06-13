#include "pam_auth.h"

#include <security/pam_appl.h>
#include <stdlib.h>
#include <string.h>

/* The single password the conversation replies with. Carried through PAM's
 * appdata_ptr so the conv callback stays reentrant (one per authenticate). */
struct conv_data {
    const char *password;
};

/* PAM conversation: answer every prompt-for-secret / prompt-with-echo message
 * with the captured password; ack info/error messages with no response. This
 * makes password, fingerprint-fallback, and "password expired" stacks behave
 * the same as any console login — the policy lives in /etc/pam.d, not here. */
static int lumen_conv(int num_msg, const struct pam_message **msg,
                      struct pam_response **resp, void *appdata_ptr)
{
    if (num_msg <= 0 || num_msg > PAM_MAX_NUM_MSG)
        return PAM_CONV_ERR;

    struct conv_data *d = (struct conv_data *) appdata_ptr;
    struct pam_response *replies = calloc((size_t) num_msg, sizeof(struct pam_response));
    if (replies == NULL)
        return PAM_BUF_ERR;

    for (int i = 0; i < num_msg; i++) {
        replies[i].resp_retcode = 0;
        switch (msg[i]->msg_style) {
        case PAM_PROMPT_ECHO_OFF:
        case PAM_PROMPT_ECHO_ON:
            replies[i].resp = strdup(d->password != NULL ? d->password : "");
            if (replies[i].resp == NULL) {
                for (int j = 0; j < i; j++)
                    free(replies[j].resp);
                free(replies);
                return PAM_BUF_ERR;
            }
            break;
        default:
            /* PAM_TEXT_INFO / PAM_ERROR_MSG: nothing to return. */
            replies[i].resp = NULL;
            break;
        }
    }

    *resp = replies;
    return PAM_SUCCESS;
}

int lumen_pam_authenticate(const char *service, const char *user, const char *password)
{
    struct conv_data data = { password };
    struct pam_conv conv = { lumen_conv, &data };
    pam_handle_t *pamh = NULL;

    int rc = pam_start(service, user, &conv, &pamh);
    if (rc != PAM_SUCCESS) {
        if (pamh != NULL)
            pam_end(pamh, rc);
        return rc;
    }

    rc = pam_authenticate(pamh, 0);
    if (rc == PAM_SUCCESS)
        rc = pam_acct_mgmt(pamh, 0);

    /* Reinitialise credentials on success so the `auth`-phase keyring unlock
     * (pam_gnome_keyring) is committed for the live session. We do NOT open a
     * new PAM session — logind already owns the user's session; we are merely
     * re-authenticating to drop the lock. */
    if (rc == PAM_SUCCESS)
        pam_setcred(pamh, PAM_REINITIALIZE_CRED);

    pam_end(pamh, rc);
    return rc;
}
