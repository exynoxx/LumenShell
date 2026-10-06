#ifndef WLHOOKS_H
#define WLHOOKS_H

#include <wayland-client.h>

#include "protocols/seat.h"
#include "protocols/toplevel.h"
#include "protocols/output.h"
#include "protocols/output_management.h"
#include "protocols/idle_notify.h"   // idle_notify_cb, used in the prototypes below

extern struct wl_display *wl_display;

// Init for clients that already own a wl_display (e.g. a GTK app using
// gdk_wayland_display_get_wl_display()). Binds only the foreign-toplevel
// slice. The caller keeps ownership of the wl_display and is responsible for
// dispatch — typically GDK's internal GSource pumps events automatically.
int  wlhooks_init_toplevel_with_display(struct wl_display *external);

// Tear down what wlhooks_init_toplevel_with_display() bound. Does NOT
// disconnect the wl_display (the caller owns it).
void wlhooks_destroy_toplevel(void);

// ext-idle-notify-v1 (lumen-lockscreen idle auto-lock). Like the toplevel
// init, binds on a caller-owned wl_display and leaves dispatch to GDK. init
// returns 0 if the notifier was bound, -1 otherwise. See protocols/idle_notify.h.
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
