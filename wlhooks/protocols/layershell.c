#include "layershell.h"
#include "registry.h"
#include "compositor.h"
#include "output.h"
#include "seat.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define LAYER_SHELL_MAX_VERSION 4

static struct zwlr_layer_shell_v1   *layer_shell = NULL;
static uint32_t                      layer_shell_version = 1;
static struct wl_surface            *surface = NULL;
static struct zwlr_layer_surface_v1 *layer_surface = NULL;

extern bool grab_keyboard; // owned by seat.c; module-private linkage retained for compat

static void layer_surface_config(void *data,
                                 struct zwlr_layer_surface_v1 *ls,
                                 uint32_t serial,
                                 uint32_t width,
                                 uint32_t height) {
    zwlr_layer_surface_v1_ack_configure(ls, serial);
    wl_surface_commit((struct wl_surface*)data);
}

static void layer_surface_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
    // Compositor asked us to go away. Drop our handles; caller decides whether
    // to recreate.
    layer_shell_destroy();
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_config,
    .closed    = layer_surface_closed,
};

static void layer_shell_registry_handler(void *data, struct wl_registry *registry,
                                         uint32_t name, const char *interface,
                                         uint32_t version) {
    layer_shell_version = version > LAYER_SHELL_MAX_VERSION ? LAYER_SHELL_MAX_VERSION : version;
    layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, layer_shell_version);
}

void layer_shell_init(void) {
    registry_add_handler("zwlr_layer_shell_v1", layer_shell_registry_handler, NULL);
}

void layer_shell_cleanup(void) {
    layer_shell_destroy();
    if (layer_shell) {
        zwlr_layer_shell_v1_destroy(layer_shell);
        layer_shell = NULL;
    }
}

void layer_shell_destroy(void) {
    if (layer_surface) {
        zwlr_layer_surface_v1_destroy(layer_surface);
        layer_surface = NULL;
    }
    if (surface) {
        wl_surface_destroy(surface);
        surface = NULL;
    }
}

struct wl_surface *layer_shell_create_surface(const char *layer_name, int width, int height,
                                              Anchor anchor, bool exclusive_zone, int exclusive_zone_height) {
    if (!layer_shell) {
        fprintf(stderr, "Layer shell protocol not available\n");
        return NULL;
    }

    struct wl_compositor *compositor = get_compositor();
    if (!compositor) {
        fprintf(stderr, "Compositor not available\n");
        return NULL;
    }

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
        wl_surface_destroy(surface);
        surface = NULL;
        return NULL;
    }

    if (grab_keyboard) {
        uint32_t mode = ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE;
        if (layer_shell_version >= ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND_SINCE_VERSION) {
            mode = ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND;
        }
        zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface, mode);
    }

    zwlr_layer_surface_v1_set_anchor(layer_surface, (enum zwlr_layer_surface_v1_anchor) anchor);
    zwlr_layer_surface_v1_set_size(layer_surface, width, height);
    if (exclusive_zone) {
        if (exclusive_zone_height <= 0)
            exclusive_zone_height = height;
        zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, exclusive_zone_height);
    }
    zwlr_layer_surface_v1_add_listener(layer_surface, &layer_surface_listener, surface);
    wl_surface_commit(surface);

    return surface;
}

struct wl_surface *layer_shell_get_surface(void) {
    return surface;
}

void layer_shell_set_input_region(int x, int y, int w, int h) {
    if (!surface) return;
    struct wl_compositor *compositor = get_compositor();
    if (!compositor) return;
    struct wl_region *region = wl_compositor_create_region(compositor);
    wl_region_add(region, x, y, w, h);
    wl_surface_set_input_region(surface, region);
    wl_region_destroy(region);
    wl_surface_commit(surface);
}
