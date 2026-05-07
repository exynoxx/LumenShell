#include "output.h"
#include "registry.h"
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OUTPUT_MAX_VERSION 4
#define MAX_OUTPUTS 8

typedef struct {
    struct wl_output *proxy;
    uint32_t          name;       // registry name (for global_remove)
    int32_t           width;
    int32_t           height;
    int32_t           scale;
    bool              has_mode;
} output_entry_t;

static output_entry_t outputs[MAX_OUTPUTS];
static int outputs_count = 0;

// Aggregated "primary" view exposed via the legacy single-output API.
// Defined as the first output that reports a current mode.
static surface_size_t primary_size = { 0, 0 };
static int32_t        primary_scale = 1;

static output_entry_t *find_by_proxy(struct wl_output *proxy) {
    for (int i = 0; i < outputs_count; i++) {
        if (outputs[i].proxy == proxy) return &outputs[i];
    }
    return NULL;
}

static void recompute_primary(void) {
    for (int i = 0; i < outputs_count; i++) {
        if (outputs[i].has_mode) {
            primary_size.width  = outputs[i].width;
            primary_size.height = outputs[i].height;
            primary_scale       = outputs[i].scale > 0 ? outputs[i].scale : 1;
            return;
        }
    }
}

static void output_geometry(void *data, struct wl_output *wl_output,
                            int32_t x, int32_t y,
                            int32_t physical_width, int32_t physical_height,
                            int32_t subpixel,
                            const char *make, const char *model,
                            int32_t transform) {}

static void output_mode(void *data, struct wl_output *wl_output,
                        uint32_t flags, int32_t width, int32_t height,
                        int32_t refresh) {
    if (!(flags & WL_OUTPUT_MODE_CURRENT)) return;
    output_entry_t *o = find_by_proxy(wl_output);
    if (!o) return;
    o->width    = width;
    o->height   = height;
    o->has_mode = true;
}

static void output_done(void *data, struct wl_output *wl_output) {
    recompute_primary();
}

static void output_scale(void *data, struct wl_output *wl_output, int32_t factor) {
    output_entry_t *o = find_by_proxy(wl_output);
    if (!o) return;
    o->scale = factor;
}

static void output_name(void *data, struct wl_output *wl_output, const char *name) {}
static void output_description(void *data, struct wl_output *wl_output, const char *description) {}

static const struct wl_output_listener output_listener = {
    .geometry    = output_geometry,
    .mode        = output_mode,
    .done        = output_done,
    .scale       = output_scale,
    .name        = output_name,
    .description = output_description,
};

static void output_handler(void *user_data, struct wl_registry *registry,
                           uint32_t name, const char *interface, uint32_t version) {
    if (outputs_count >= MAX_OUTPUTS) {
        fprintf(stderr, "output: ignoring extra output, cap=%d\n", MAX_OUTPUTS);
        return;
    }

    uint32_t v = version > OUTPUT_MAX_VERSION ? OUTPUT_MAX_VERSION : version;
    output_entry_t *o = &outputs[outputs_count++];
    memset(o, 0, sizeof(*o));
    o->proxy = wl_registry_bind(registry, name, &wl_output_interface, v);
    o->name  = name;
    o->scale = 1;
    wl_output_add_listener(o->proxy, &output_listener, NULL);
}

static void output_remove_handler(void *user_data, struct wl_registry *registry, uint32_t name) {
    for (int i = 0; i < outputs_count; i++) {
        if (outputs[i].name != name) continue;
        wl_output_destroy(outputs[i].proxy);
        outputs[i] = outputs[--outputs_count];
        recompute_primary();
        return;
    }
}

void output_init(void) {
    registry_add_handler("wl_output", output_handler, NULL);
    registry_set_remover("wl_output", output_remove_handler);
}

void output_destroy(void) {
    for (int i = 0; i < outputs_count; i++) {
        if (outputs[i].proxy) wl_output_destroy(outputs[i].proxy);
    }
    outputs_count = 0;
}

surface_size_t *get_screen_size(void) { return &primary_size; }
int32_t         get_output_scale(void) { return primary_scale; }

struct wl_output *output_get_primary(void) {
    for (int i = 0; i < outputs_count; i++) {
        if (outputs[i].has_mode) return outputs[i].proxy;
    }
    return outputs_count > 0 ? outputs[0].proxy : NULL;
}
