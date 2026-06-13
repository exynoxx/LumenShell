#ifndef LUMEN_PAM_AUTH_H
#define LUMEN_PAM_AUTH_H

/* Run the full PAM auth + account stack for `service` as `user`, feeding
 * `password` to every echo-off/echo-on prompt. Blocking — call off the main
 * thread. Returns 0 (PAM_SUCCESS) on success, the PAM error code otherwise.
 *
 * The `auth` stack running here is also what hands the typed password to
 * pam_gnome_keyring (see data/pam.d/lumen-lockscreen), unlocking the login
 * keyring on a successful unlock. The password buffer is never logged. */
int lumen_pam_authenticate(const char *service, const char *user, const char *password);

#endif /* LUMEN_PAM_AUTH_H */
