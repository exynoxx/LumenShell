#ifndef IDLE_NOTIFY_H
#define IDLE_NOTIFY_H

#include <stdbool.h>
#include <stdint.h>
#include <wayland-client.h>

// ext-idle-notify-v1 client. Additive wlhooks surface used by lumen-lockscreen
// to self-lock on inactivity (no external idle daemon needed). Binds on a
// caller-owned wl_display (GTK's), exactly like the toplevel/activation hooks —
// the GDK main loop dispatches the idled/resumed events.

typedef void (*idle_notify_cb)(void *user_data);

// Register the ext_idle_notifier_v1 registry handler. Call BEFORE registry_init.
void idle_notify_init(void);
void idle_notify_cleanup(void);

// True once the compositor's ext_idle_notifier_v1 global has been bound.
bool idle_notify_available(void);

// Arm a single idle notification for `timeout_ms` of inactivity on the seat.
// `idled` fires when the seat goes idle, `resumed` on the next input. Replaces
// any previously-armed notification. Returns 0 on success, -1 if the protocol
// or a seat is unavailable.
int idle_notify_register(uint32_t timeout_ms,
                         idle_notify_cb idled, void *idled_data,
                         idle_notify_cb resumed, void *resumed_data);

// Tear down the armed notification (e.g. while already locked, so we don't
// re-fire). Safe to call when nothing is armed.
void idle_notify_unregister(void);

#endif // IDLE_NOTIFY_H
