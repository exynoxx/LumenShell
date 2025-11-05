#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "liblayershell.h"
#include "egl.h"
#include "registry.h"

int init_layer_shell(const char *layer_name, int width, int height, Anchor anchor, bool exclusive_zone) {
    display = wl_display_connect(NULL);
    if (!display) { 
        fprintf(stderr,"Failed to connect to Wayland display\n"); 
        return -1; 
    }

    compositor_init();
    layer_shell_init();
    seat_init();
    toplevel_init();

    registry_init(display);

    struct wl_surface *surface = layer_shell_create_surface(layer_name, width, height, anchor, exclusive_zone);
    egl_init(display, surface, width, height);

    return 0;
}

struct wl_display *get_wl_display(){
    return display;
}

void destroy_layer_shell(void) {
    compositor_cleanup();
    layer_shell_cleanup();
    toplevel_cleanup();
    egl_cleanup();
    registry_cleanup();
}
