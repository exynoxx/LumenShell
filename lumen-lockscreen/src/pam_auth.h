#ifndef LUMEN_PAM_AUTH_H
#define LUMEN_PAM_AUTH_H

/* Blocking — call off the main thread. Returns PAM_SUCCESS (0) or the PAM
 * error code. Never log the password buffer. */
int lumen_pam_authenticate(const char *service, const char *user, const char *password);

#endif /* LUMEN_PAM_AUTH_H */
