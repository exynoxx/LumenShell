#ifndef WLHOOKS_H
#define WLHOOKS_H

#include <wayland-client.h>

#include "protocols/seat.h"
#include "protocols/toplevel.h"
#include "protocols/output.h"
#include "protocols/output_management.h"
#include "protocols/idle_notify.h"   // idle_notify_cb, used in the prototypes below

extern struct wl_display *wl_display;

// Binds foreign-toplevel (+ seat, outputs) on a caller-owned wl_display (GTK's);
// the caller keeps ownership and GDK's GSource does the dispatch.
int  wlhooks_init_toplevel_with_display(struct wl_display *external);

// Tear down what wlhooks_init_toplevel_with_display() bound. Does NOT
// disconnect the wl_display (the caller owns it).
void wlhooks_destroy_toplevel(void);

// ext-idle-notify-v1 on a caller-owned wl_display, dispatched by GDK.
// init returns 0 if the notifier was bound, -1 otherwise.
int  wlhooks_idle_notify_init(struct wl_display *external);
void wlhooks_idle_notify_destroy(void);
int  wlhooks_idle_notify_register(uint32_t timeout_ms,
                                  idle_notify_cb idled, void *idled_data,
                                  idle_notify_cb resumed, void *resumed_data);
void wlhooks_idle_notify_unregister(void);
bool wlhooks_idle_notify_available(void);

// zwp-idle-inhibit-v1 (lumen-panel Caffeine). Own registry on the caller's
// wl_display; see protocols/idle_inhibit.h.
int  wlhooks_idle_inhibit_init(struct wl_display *external);
int  wlhooks_idle_inhibit_set(struct wl_surface *surface, bool on);

#endif // WLHOOKS_H
