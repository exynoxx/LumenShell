#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "wlhooks.h"
#include "egl.h"
#include "registry.h"

struct wl_display *wl_display = NULL;

int wlhooks_init(){
    wl_display = wl_display_connect(NULL);
    if (!wl_display) { 
        fprintf(stderr,"Failed to connect to Wayland display\n"); 
        return -1; 
    }

    compositor_init();
    layer_shell_init();
    seat_init();
    toplevel_init();
    output_init();
    //screencopy_init();

    registry_init(wl_display);
}

int init_layer_shell(const char *layer_name, int width, int height, Anchor anchor, bool exclusive_zone, int exclusive_zone_height) {
    struct wl_surface *surface = layer_shell_create_surface(layer_name, width, height, anchor, exclusive_zone, exclusive_zone_height);

    int32_t scale = get_output_scale();
    if (scale < 1) scale = 1;
    // Set buffer scale as pending state — applied in the next wl_surface_commit
    // (the layer-shell configure callback or first eglSwapBuffers)
    wl_surface_set_buffer_scale(surface, scale);

    egl_init(wl_display, surface, width * scale, height * scale);

    return 0;
}

struct wl_display *get_wl_display(){
    return wl_display;
}

int display_dispatch_blocking(){
    return wl_display_dispatch(wl_display);
}

void wlhooks_destroy(void) {
    compositor_cleanup();
    layer_shell_cleanup();
    seat_cleanup();
    toplevel_cleanup();
    egl_cleanup();
    registry_cleanup();
    output_destroy();
    //screencopy_cleanup();

    wl_display_disconnect(wl_display);
}
