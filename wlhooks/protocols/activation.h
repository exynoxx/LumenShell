#ifndef ACTIVATION_H
#define ACTIVATION_H

#include <stdbool.h>

void activation_init(void);
void activation_cleanup(void);
bool activation_available(void);

// Synchronously requests an XDG activation token for launching `app_id`.
// Performs a wl_display roundtrip. Returns a heap-allocated string the caller
// must free, or NULL on failure / if the protocol is unavailable.
char *activation_get_token(const char *app_id);

// Convenience: request a token and activate the layer-shell surface with it.
// Useful when the panel itself wants focus (e.g. on popup show).
void activation_activate_self(void);

#endif
