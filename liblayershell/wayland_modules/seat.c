#include "seat.h"
#include "registry.h"

static struct wl_seat *seat = NULL;
static dk_mouse_info mouse_info = {0};

// Your existing seat listener code
static void pointer_enter(void *data, struct wl_pointer *pointer,
                         uint32_t serial, struct wl_surface *surface,
                         wl_fixed_t x, wl_fixed_t y) {
    dk_mouse_info *info = data;
    info->mouse_x = wl_fixed_to_double(x);
    info->mouse_y = wl_fixed_to_double(y);
}

static void pointer_motion(void *data, struct wl_pointer *pointer,
                          uint32_t time, wl_fixed_t x, wl_fixed_t y) {
    dk_mouse_info *info = data;
    info->mouse_x = wl_fixed_to_double(x);
    info->mouse_y = wl_fixed_to_double(y);
}

static void pointer_button(void *data, struct wl_pointer *pointer,
                          uint32_t serial, uint32_t time, uint32_t button,
                          uint32_t state) {
    dk_mouse_info *info = data;
    if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
        info->mouse_buttons |= (1 << button);
    } else {
        info->mouse_buttons &= ~(1 << button);
    }
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter,
    .leave = NULL,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = NULL,
};

static void seat_capabilities(void *data, struct wl_seat *seat,
                             uint32_t caps) {
    if (caps & WL_SEAT_CAPABILITY_POINTER) {
        struct wl_pointer *pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer, &pointer_listener, data);
    }
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = NULL,
};

static void seat_registry_handler(void *data, struct wl_registry *registry,
                                 uint32_t name, const char *interface,
                                 uint32_t version) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 5);
    wl_seat_add_listener(seat, &seat_listener, &mouse_info);
}

void seat_init(void) {
    registry_add_handler(wl_seat_interface.name, 
                        seat_registry_handler, NULL);
}

dk_mouse_info *seat_mouse_info(void) {
    return &mouse_info;
}