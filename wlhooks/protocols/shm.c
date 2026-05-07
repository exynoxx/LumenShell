#include "shm.h"
#include "registry.h"
#include <wayland-client.h>

static struct wl_shm *shm = NULL;

static void registry_handler(void *data, struct wl_registry *registry,
                             uint32_t name, const char *interface,
                             uint32_t version) {
    shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
}

void shm_init(void) {
    registry_add_handler("wl_shm", registry_handler, NULL);
}

void shm_cleanup(void) {
    if (shm) {
        wl_shm_destroy(shm);
        shm = NULL;
    }
}

struct wl_shm *get_wl_shm(void) {
    return shm;
}
