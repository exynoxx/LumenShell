#include "seat.h"
#include "registry.h"

#include <wayland-client.h>

#define SEAT_MAX_VERSION 5

static struct wl_seat *seat = NULL;

static void seat_registry_handler(void *data, struct wl_registry *registry,
                                  uint32_t name, const char *interface,
                                  uint32_t version) {
    // Take only the first advertised seat; multi-seat support is out of scope.
    if (seat) return;
    uint32_t v = version > SEAT_MAX_VERSION ? SEAT_MAX_VERSION : version;
    seat = wl_registry_bind(registry, name, &wl_seat_interface, v);
}

void seat_init(void) {
    registry_add_handler(wl_seat_interface.name, seat_registry_handler, NULL);
}

struct wl_seat *get_wl_seat(void) {
    return seat;
}
