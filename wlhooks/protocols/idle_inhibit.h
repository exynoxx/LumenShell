#ifndef IDLE_INHIBIT_H
#define IDLE_INHIBIT_H

#include <stdbool.h>
#include <wayland-client.h>

// zwp_idle_inhibit_manager_v1 client (lumen-panel Caffeine). Uses its own
// wl_registry on the caller-owned wl_display, so it is independent of the
// shared registry and of whichever other wlhooks init ran first.

// Bind the inhibit manager. Returns 0 if bound, -1 if the compositor lacks it.
int idle_inhibit_init(struct wl_display *display);

// Create (on=true) or destroy (on=false) the single inhibitor on `surface`.
// The compositor honours it while the surface is mapped. Returns 0 on success.
int idle_inhibit_set(struct wl_surface *surface, bool on);

#endif // IDLE_INHIBIT_H
