#include "wlhooks.h"
#include "registry.h"
#include "protocols/seat.h"
#include "protocols/toplevel.h"
#include "protocols/output.h"
#include "protocols/idle_notify.h"
#include "protocols/idle_inhibit.h"

int wlhooks_init_toplevel_with_display(struct wl_display *external) {
    if (!external) return -1;

    toplevel_init();
    seat_init();
    // Bind wl_output too so foreign-toplevel output_enter/leave can be mapped
    // to connector names (per-monitor taskbar filtering). Read-only listeners.
    output_init();

    registry_init(external);
    return 0;
}

// ---- ext-idle-notify-v1 (lumen-lockscreen idle auto-lock) ------------------
int wlhooks_idle_notify_init(struct wl_display *external) {
    if (!external) return -1;

    seat_init();
    idle_notify_init();

    registry_init(external);
    return idle_notify_available() ? 0 : -1;
}

int wlhooks_idle_notify_register(uint32_t timeout_ms,
                                 idle_notify_cb idled, void *idled_data,
                                 idle_notify_cb resumed, void *resumed_data) {
    return idle_notify_register(timeout_ms, idled, idled_data, resumed, resumed_data);
}

void wlhooks_idle_notify_unregister(void) {
    idle_notify_unregister();
}

bool wlhooks_idle_notify_available(void) {
    return idle_notify_available();
}

// ---- zwp-idle-inhibit-v1 (lumen-panel Caffeine) ----------------------------
int wlhooks_idle_inhibit_init(struct wl_display *external) {
    return idle_inhibit_init(external);
}

int wlhooks_idle_inhibit_set(struct wl_surface *surface, bool on) {
    return idle_inhibit_set(surface, on);
}
