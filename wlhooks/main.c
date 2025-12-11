#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "wlhooks.h"
#include "egl.h"
#include "registry.h"

struct wl_display *wl_display = NULL;

//TODO enable disable keyboar.

int init_layer_shell(const char *layer_name, int width, int height, Anchor anchor, bool exclusive_zone) {
    wl_display = wl_display_connect(NULL);
    if (!wl_display) { 
        fprintf(stderr,"Failed to connect to Wayland display\n"); 
        return -1; 
    }

    compositor_init();
    layer_shell_init();
    seat_init();
    toplevel_init();

    registry_init(wl_display);

    struct wl_surface *surface = layer_shell_create_surface(layer_name, width, height, anchor, exclusive_zone);
    egl_init(wl_display, surface, width, height);

    return 0;
}

struct wl_display *get_wl_display(){
    return wl_display;
}

int display_dispatch_blocking(){
    return wl_display_dispatch(wl_display);
}

void destroy(void) {
    compositor_cleanup();
    layer_shell_cleanup();
    seat_cleanup();
    toplevel_cleanup();
    egl_cleanup();
    registry_cleanup();

    wl_display_disconnect(wl_display);
}
