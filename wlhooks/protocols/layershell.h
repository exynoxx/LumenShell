#ifndef LAYER_SHELL_H
#define LAYER_SHELL_H

#include <wayland-client.h>
#include <stdbool.h>
#include <wayland-egl.h>
#include "../generated/wlr-layer-shell-unstable-v1-client-protocol.h"

typedef enum {
    UP = 1,
	DOWN = 2,
	LEFT = 4,
	RIGHT = 8,
    TOP = 13,
    BOTTOM = 14
} Anchor;

typedef struct surface_size_t {
    int width;
    int height;
} surface_size_t;

void layer_shell_init();
void layer_shell_cleanup();

struct wl_surface *layer_shell_create_surface(const char *layer_name, int width, int height, Anchor anchor, bool exclusive_zone);
struct wl_surface *layer_shell_get_surface(void);
surface_size_t *get_layer_shell_size();

#endif // LAYER_SHELL_H