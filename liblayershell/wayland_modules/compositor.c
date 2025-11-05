#include "registry.h"
#include "compositor.h"

static struct wl_compositor *compositor = NULL;

static void compositor_registry_handler(void *data, struct wl_registry *registry,
                                       uint32_t name, const char *interface,
                                       uint32_t version) {
    compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
}

void compositor_init(void) {
    registry_add_handler("wl_compositor", compositor_registry_handler, NULL);
}

void compositor_cleanup(){
    wl_compositor_destroy(compositor); 
    compositor = NULL;
}

struct wl_compositor *get_compositor(void) {
    return compositor;
}