#ifndef LAYER_SHELL_H
#define LAYER_SHELL_H

#include <wayland-client.h>
#include <wayland-egl.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

typedef enum {
    TOP,
    BOTTOM
} EDGE;

void layer_shell_module_init(void);
int layer_shell_create_surface(const char *layer_name, int width, int height, EDGE edge);
struct wl_surface *layer_shell_get_surface(void);
struct wl_egl_window *layer_shell_get_egl_window(void);

#endif // LAYER_SHELL_H