#include "output.h"
#include "registry.h"
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>

struct wl_output *wl_output;
static surface_size_t *surface_size;
static int32_t scale_factor = 1;

static void output_geometry(void *data, struct wl_output *wl_output,
                           int32_t x, int32_t y,
                           int32_t physical_width, int32_t physical_height,
                           int32_t subpixel,
                           const char *make, const char *model,
                           int32_t transform) {
    // Physical dimensions in mm - not what you usually want
}

static void output_mode(void *data, struct wl_output *wl_output,
                       uint32_t flags, int32_t width, int32_t height,
                       int32_t refresh) {
    //printf("output mode %d, %d\n", width, height);
    /* if (flags & WL_OUTPUT_MODE_CURRENT) {
    }*/
    surface_size->width = width;
    surface_size->height = height;
}

static void output_done(void *data, struct wl_output *wl_output) {
    // All output events have been sent
}

static void output_scale(void *data, struct wl_output *wl_output,
                        int32_t factor) {
    scale_factor = factor;
}

static void name(void *data, struct wl_output *wl_output,const char *name) {

}

static void description(void *data, struct wl_output *wl_output, const char *description){

}

static const struct wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
    .name = name,
    .description = description
};

static void output_handler(void *user_data, struct wl_registry *registry,
                           uint32_t name, const char *interface, uint32_t version) {
    wl_output = wl_registry_bind(registry, name, &wl_output_interface, version);
    wl_output_add_listener(wl_output, &output_listener, NULL);
}

void output_init(void) {
    surface_size = malloc(sizeof(surface_size_t));
    registry_add_handler("wl_output", output_handler, NULL);
}

void output_destroy(){
    free(surface_size);
}

surface_size_t *get_screen_size(){ return surface_size; }
int32_t get_output_scale(){ return scale_factor; }
