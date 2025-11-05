#include "layershell.h"
#include "registry.h"
#include "compositor.h"
#include <stdio.h>
#include <string.h>
#include "../wayland/wlr-layer-shell-unstable-v1-client-protocol.h"

static struct zwlr_layer_shell_v1 *layer_shell = NULL;
static struct wl_surface *surface = NULL;
static struct zwlr_layer_surface_v1 *layer_surface = NULL;

// --- Layer surface listener ---
static void layer_surface_config(void *data,
                                           struct zwlr_layer_surface_v1 *surface,
                                           uint32_t serial,
                                           uint32_t width,
                                           uint32_t height) {
    zwlr_layer_surface_v1_ack_configure(surface, serial);
    wl_surface_commit((struct wl_surface*)data);
}

static void layer_surface_closed(void *data, struct zwlr_layer_surface_v1 *surface) {
    // Handle cleanup if needed
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_config,
    .closed = layer_surface_closed
};

// --- Registry handler ---
static void layer_shell_registry_handler(void *data, struct wl_registry *registry,
                                        uint32_t name, const char *interface,
                                        uint32_t version) {
    layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
}

void layer_shell_init(void) {
    registry_add_handler("zwlr_layer_shell_v1", layer_shell_registry_handler, NULL);
}

void layer_shell_cleanup(void){
    if (surface) { 
        wl_surface_destroy(surface);
        surface = NULL; 
    }

    if (layer_shell) { 
        zwlr_layer_shell_v1_destroy(layer_shell); 
        layer_shell = NULL; 
    }
}

struct wl_surface *layer_shell_create_surface(const char *layer_name, int width, int height, EDGE edge) {
    if (!layer_shell) {
        fprintf(stderr, "Layer shell protocol not available\n");
        return NULL;
    }

    struct wl_compositor *compositor = get_compositor();
    if (!compositor) {
        fprintf(stderr, "Compositor not available\n");
        return NULL;
    }

    // Create surface
    surface = wl_compositor_create_surface(compositor);
    if (!surface) {
        fprintf(stderr, "Failed to create surface\n");
        return NULL;
    }

    layer_surface = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell,
        surface,
        NULL,
        ZWLR_LAYER_SHELL_V1_LAYER_TOP,
        layer_name
    );

    if (!layer_surface) {
        fprintf(stderr, "Failed to create layer surface\n");
        return NULL;
    }

    enum zwlr_layer_surface_v1_anchor anchor_bits =
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;

    if (edge == TOP) {
        anchor_bits |= ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP;
    } else if (edge == BOTTOM) {
        anchor_bits |= ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
    }

    zwlr_layer_surface_v1_set_anchor(layer_surface, anchor_bits);
    zwlr_layer_surface_v1_set_size(layer_surface, width, height);
    zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, height);
    zwlr_layer_surface_v1_add_listener(layer_surface, &layer_surface_listener, surface);
    wl_surface_commit(surface);

    return surface;
}

struct wl_surface *layer_shell_get_surface(void) {
    return surface;
}