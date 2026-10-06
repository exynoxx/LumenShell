#include "wlhooks.h"
#include "registry.h"
#include "protocols/seat.h"
#include "protocols/toplevel.h"
#include "protocols/output.h"
#include "protocols/idle_notify.h"
#include "protocols/idle_inhibit.h"

struct wl_display *wl_display = NULL;

// Init for clients that already own a wl_display (a GTK app via
// gdk_wayland_display_get_wl_display()). Binds the foreign-toplevel slice
// only. The caller keeps ownership of the wl_display and is responsible for
// dispatch — GDK's internal GSource pumps events automatically.
int wlhooks_init_toplevel_with_display(struct wl_display *external) {
    if (!external) return -1;
    wl_display = external;


    toplevel_init();
    seat_init();
    // Bind wl_output too so foreign-toplevel output_enter/leave can be mapped
    // to connector names (per-monitor taskbar filtering). Read-only listeners.
    output_init();

    registry_init(wl_display);
    return 0;
}

void wlhooks_destroy_toplevel(void) {
    toplevel_cleanup();
    output_destroy();
    seat_cleanup();
    registry_cleanup();
    // Do NOT disconnect: the caller (GTK/GDK) owns the wl_display.
    wl_display = NULL;
}

// ---- ext-idle-notify-v1 (lumen-lockscreen idle auto-lock) ------------------
// Minimal init on a caller-owned wl_display (GTK's): bind wl_seat + the idle
// notifier, then let the GDK main loop dispatch idled/resumed events. Self-
// contained — the lockscreen needs neither toplevel nor activation hooks.
int wlhooks_idle_notify_init(struct wl_display *external) {
    if (!external) return -1;
    wl_display = external;

    seat_init();
    idle_notify_init();

    registry_init(wl_display);
    return idle_notify_available() ? 0 : -1;
}

void wlhooks_idle_notify_destroy(void) {
    idle_notify_cleanup();
    seat_cleanup();
    registry_cleanup();
    // Do NOT disconnect: GTK/GDK owns the wl_display.
    wl_display = NULL;
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
