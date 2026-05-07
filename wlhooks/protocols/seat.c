#include "seat.h"
#include "registry.h"
#include "pointer.h"
#include "keyboard.h"

#include <stdio.h>
#include <wayland-client.h>

#define SEAT_MAX_VERSION 5

static struct wl_seat *seat = NULL;
static bool grab_keyboard_flag = false;
static uint32_t last_input_serial = 0;

static void on_capabilities(void *data, struct wl_seat *s, uint32_t capabilities) {
    if (capabilities & WL_SEAT_CAPABILITY_POINTER) {
        pointer_attach(wl_seat_get_pointer(s));
    }
    if ((capabilities & WL_SEAT_CAPABILITY_KEYBOARD) && grab_keyboard_flag) {
        keyboard_attach(wl_seat_get_keyboard(s));
    }
}

static void on_name(void *data, struct wl_seat *s, const char *name) {}

static const struct wl_seat_listener seat_listener = {
    .capabilities = on_capabilities,
    .name         = on_name,
};

static void seat_registry_handler(void *data, struct wl_registry *registry,
                                  uint32_t name, const char *interface,
                                  uint32_t version) {
    // Take only the first advertised seat; multi-seat support is out of scope.
    if (seat) return;
    uint32_t v = version > SEAT_MAX_VERSION ? SEAT_MAX_VERSION : version;
    seat = wl_registry_bind(registry, name, &wl_seat_interface, v);
    wl_seat_add_listener(seat, &seat_listener, NULL);
}

void seat_init(void) {
    keyboard_init();
    registry_add_handler(wl_seat_interface.name, seat_registry_handler, NULL);
}

void seat_cleanup(void) {
    keyboard_cleanup();
    pointer_release();
    if (seat) {
        wl_seat_release(seat);
        seat = NULL;
    }
}

void set_grab_keyboard(bool value) {
    grab_keyboard_flag = value;
}

bool seat_should_grab_keyboard(void) {
    return grab_keyboard_flag;
}

struct wl_seat *get_wl_seat(void) {
    return seat;
}

uint32_t seat_get_last_serial(void) {
    return last_input_serial;
}

void seat_set_last_serial(uint32_t serial) {
    last_input_serial = serial;
}
