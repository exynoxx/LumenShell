#include <stdio.h>

#include "wlhooks.h"
#include "egl.h"
#include "registry.h"
#include "protocols/seat.h"
#include "protocols/toplevel.h"
#include "protocols/activation.h"

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

    registry_init(wl_display);
    return 0;
}

void wlhooks_destroy_toplevel(void) {
    activation_cleanup();
    toplevel_cleanup();
    seat_cleanup();
    registry_cleanup();
    // Do NOT disconnect: the caller (GTK/GDK) owns the wl_display.
    wl_display = NULL;
}
