#ifndef LAYER_SHELL_H
#define LAYER_SHELL_H

#include <wayland-client.h>
#include <wayland-egl.h>
#include "../wayland/wlr-layer-shell-unstable-v1-client-protocol.h"

typedef enum {
    TOP,
    BOTTOM
} EDGE;

void layer_shell_init(void);
struct wl_surface *layer_shell_create_surface(const char *layer_name, int width, int height, EDGE edge);
struct wl_surface *layer_shell_get_surface(void);

#endif // LAYER_SHELL_H