#include "seat.h"
#include "registry.h"
#include <stdio.h>

static struct wl_seat *seat = NULL;
static dk_mouse_info mouse_info = {0};

static seat_mouse_enter mouse_enter_cb;
static void *mouse_enter_userdata = NULL;

static seat_mouse_leave mouse_leave_cb;
static void *mouse_leave_userdata = NULL;

// Your existing seat listener code
static void pointer_enter(void *data, struct wl_pointer *pointer,
                         uint32_t serial, struct wl_surface *surface,
                         wl_fixed_t x, wl_fixed_t y) {
    dk_mouse_info *info = data;
    info->mouse_x = wl_fixed_to_double(x);
    info->mouse_y = wl_fixed_to_double(y);

    if(mouse_enter_cb){
        mouse_enter_cb(mouse_enter_userdata);
    }
}

void pointer_leave(void *data, struct wl_pointer *wl_pointer,uint32_t serial, struct wl_surface *surface) {
    dk_mouse_info *info = data;
    info->mouse_x = -1;
    info->mouse_y = -1;
    if(mouse_leave_cb){
        mouse_leave_cb(mouse_leave_userdata);
    }
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

void pointer_axis(void *data, struct wl_pointer *wl_pointer,
                        uint32_t time, uint32_t axis, wl_fixed_t value) {
    // Scroll events - can be empty for now
}

void pointer_frame(void *data, struct wl_pointer *wl_pointer) {
    // Frame complete - can be empty
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter,
    .leave = pointer_leave,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = pointer_axis,
    .frame = pointer_frame
};

static void seat_capabilities(void *data, struct wl_seat *seat,
                             uint32_t caps) {
    if (caps & WL_SEAT_CAPABILITY_POINTER) {
        struct wl_pointer *pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer, &pointer_listener, data);
    }
}

static void seat_name(void *data, struct wl_seat *seat, const char *name) {
    printf("Seat name: %s\n", name);
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

static void seat_registry_handler(void *data, struct wl_registry *registry,
                                 uint32_t name, const char *interface,
                                 uint32_t version) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 5);
    wl_seat_add_listener(seat, &seat_listener, &mouse_info);
}

void seat_init(void) {
    registry_add_handler(wl_seat_interface.name, seat_registry_handler, NULL);
}

dk_mouse_info *seat_mouse_info(void) {
    return &mouse_info;
}

void register_on_mouse_enter(seat_mouse_enter cb, void* user_data){
    mouse_enter_cb = cb;
    mouse_enter_userdata = user_data;
}
void register_on_mouse_leave(seat_mouse_leave cb, void* user_data){
    mouse_leave_cb = cb;
    mouse_leave_userdata = user_data;
}

