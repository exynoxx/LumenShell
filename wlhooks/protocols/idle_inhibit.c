#include "idle_inhibit.h"
#include "../generated/idle-inhibit-unstable-v1-client-protocol.h"

#include <string.h>
#include <stdio.h>

static struct wl_display                    *s_display  = NULL;
static struct zwp_idle_inhibit_manager_v1   *manager    = NULL;
static struct zwp_idle_inhibitor_v1         *inhibitor  = NULL;

static void reg_global(void *data, struct wl_registry *registry, uint32_t name,
                       const char *interface, uint32_t version) {
    (void) data; (void) version;
    if (strcmp(interface, zwp_idle_inhibit_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name,
                                   &zwp_idle_inhibit_manager_v1_interface, 1);
}

static void reg_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void) data; (void) registry; (void) name;
}

static const struct wl_registry_listener reg_listener = {
    .global        = reg_global,
    .global_remove = reg_remove,
};

int idle_inhibit_init(struct wl_display *display) {
    if (manager) return 0;
    if (!display) return -1;
    s_display = display;
    struct wl_registry *reg = wl_display_get_registry(display);
    wl_registry_add_listener(reg, &reg_listener, NULL);
    wl_display_roundtrip(display);
    wl_registry_destroy(reg);   // bound globals outlive the registry proxy
    return manager ? 0 : -1;
}

int idle_inhibit_set(struct wl_surface *surface, bool on) {
    if (!manager) {
        fprintf(stderr, "idle_inhibit: zwp_idle_inhibit_manager_v1 unavailable\n");
        return -1;
    }
    if (inhibitor) {
        zwp_idle_inhibitor_v1_destroy(inhibitor);
        inhibitor = NULL;
    }
    if (on) {
        if (!surface) return -1;
        inhibitor = zwp_idle_inhibit_manager_v1_create_inhibitor(manager, surface);
    }
    wl_display_flush(s_display);
    return 0;
}
