#include <stdio.h>

#include "wlhooks.h"
#include "egl.h"
#include "registry.h"
#include "protocols/seat.h"
#include "protocols/toplevel.h"
#include "protocols/activation.h"
#include "protocols/output.h"
#include "protocols/idle_notify.h"
#include "protocols/screencopy.h"

struct wl_display *wl_display = NULL;

int wlhooks_init(void) {
    wl_display = wl_display_connect(NULL);
    if (!wl_display) {
        fprintf(stderr, "Failed to connect to Wayland display\n");
        return -1;
    }

    compositor_init();
    layer_shell_init();
    seat_init();
    toplevel_init();
    output_init();
    activation_init();

    registry_init(wl_display);
    return 0;
}

struct wl_display *get_wl_display(void) {
    return wl_display;
}

int display_dispatch_blocking(void) {
    return wl_display_dispatch(wl_display);
}

void wlhooks_destroy(void) {
    // EGL must be torn down before the wl_surface it was created from. Order:
    // EGL → layer surface / wl_compositor → other proxies → registry → display.
    egl_cleanup();
    activation_cleanup();
    layer_shell_cleanup();
    toplevel_cleanup();
    output_destroy();
    seat_cleanup();
    compositor_cleanup();
    registry_cleanup();

    if (wl_display) {
        wl_display_disconnect(wl_display);
        wl_display = NULL;
    }
}

int wlhooks_init_toplevel_with_display(struct wl_display *external) {
    if (!external) return -1;
    wl_display = external;

    // GTK owns pointer/keyboard. We only need wl_seat exposed for activate().
    seat_set_minimal_mode(true);

    toplevel_init();
    seat_init();
    activation_init();
    // Bind wl_output too so foreign-toplevel output_enter/leave can be mapped
    // to connector names (per-monitor taskbar filtering). Read-only listeners.
    output_init();

    registry_init(wl_display);
    return 0;
}

void wlhooks_destroy_toplevel(void) {
    activation_cleanup();
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

    seat_set_minimal_mode(true);   // GTK owns input; we only need wl_seat exposed
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

// ---- lumen-lockscreen combined init ----------------------------------------
// A lock screen needs three read-only hooks on GTK's wl_display: idle
// (ext-idle-notify-v1, auto-lock), screencopy (wlr-screencopy, snapshot the
// desktop to blur behind the card — the desktop is gone once the session is
// locked, so we grab it just before), and wl_output (screencopy targets one).
// registry_init can only run once, so they are all bound here in a single
// pass. Use instead of wlhooks_idle_notify_init when both idle and capture are
// wanted. Availability of each is queried separately (idle_notify_available /
// screencopy via the capture failed callback).
int wlhooks_lockscreen_init(struct wl_display *external) {
    if (!external) return -1;
    wl_display = external;

    seat_set_minimal_mode(true);   // GTK owns input; we only need wl_seat for idle
    seat_init();
    idle_notify_init();
    output_init();
    screencopy_init();

    registry_init(wl_display);
    return 0;
}

void wlhooks_lockscreen_destroy(void) {
    screencopy_cleanup();
    output_destroy();
    idle_notify_cleanup();
    seat_cleanup();
    registry_cleanup();
    // Do NOT disconnect: GTK/GDK owns the wl_display.
    wl_display = NULL;
}
