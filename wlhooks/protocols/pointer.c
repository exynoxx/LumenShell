#include "pointer.h"
#include "seat.h"
#include <wayland-client.h>

static struct wl_pointer *pointer = NULL;

static seat_mouse_enter  mouse_enter_cb;   static void *mouse_enter_userdata  = NULL;
static seat_mouse_leave  mouse_leave_cb;   static void *mouse_leave_userdata  = NULL;
static seat_mouse_motion mouse_motion_cb;  static void *mouse_motion_userdata = NULL;
static seat_mouse_down   mouse_down_cb;    static void *mouse_down_userdata   = NULL;
static seat_mouse_up     mouse_up_cb;      static void *mouse_up_userdata     = NULL;
static seat_mouse_scroll mouse_scroll_cb;  static void *mouse_scroll_userdata = NULL;

static void on_enter(void *data, struct wl_pointer *p,
                     uint32_t serial, struct wl_surface *surface,
                     wl_fixed_t x, wl_fixed_t y) {
    seat_set_last_serial(serial);
    if (mouse_enter_cb) mouse_enter_cb(mouse_enter_userdata);
}

static void on_leave(void *data, struct wl_pointer *p,
                     uint32_t serial, struct wl_surface *surface) {
    seat_set_last_serial(serial);
    if (mouse_leave_cb) mouse_leave_cb(mouse_leave_userdata);
}

static void on_motion(void *data, struct wl_pointer *p,
                      uint32_t time, wl_fixed_t x, wl_fixed_t y) {
    if (mouse_motion_cb)
        mouse_motion_cb(wl_fixed_to_int(x), wl_fixed_to_int(y), mouse_motion_userdata);
}

static void on_button(void *data, struct wl_pointer *p,
                      uint32_t serial, uint32_t time, uint32_t button,
                      uint32_t state) {
    seat_set_last_serial(serial);
    if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
        if (mouse_down_cb) mouse_down_cb(button, mouse_down_userdata);
    } else {
        if (mouse_up_cb) mouse_up_cb(button, mouse_up_userdata);
    }
}

static void on_axis(void *data, struct wl_pointer *p,
                    uint32_t time, uint32_t axis, wl_fixed_t value) {
    if (axis != WL_POINTER_AXIS_VERTICAL_SCROLL) return;
    if (!mouse_scroll_cb) return;

    double amount = wl_fixed_to_double(value);
    int32_t step = 0;
    if      (amount > 0.0) step =  1;
    else if (amount < 0.0) step = -1;
    if (step != 0) mouse_scroll_cb(step, mouse_scroll_userdata);
}

static void on_frame        (void *data, struct wl_pointer *p) {}
static void on_axis_source  (void *data, struct wl_pointer *p, uint32_t source) {}
static void on_axis_discrete(void *data, struct wl_pointer *p, uint32_t axis, int32_t discrete) {}
static void on_axis_stop    (void *data, struct wl_pointer *p, uint32_t time, uint32_t axis) {}

static const struct wl_pointer_listener pointer_listener = {
    .enter         = on_enter,
    .leave         = on_leave,
    .motion        = on_motion,
    .button        = on_button,
    .axis          = on_axis,
    .frame         = on_frame,
    .axis_source   = on_axis_source,
    .axis_discrete = on_axis_discrete,
    .axis_stop     = on_axis_stop,
};

void pointer_attach(struct wl_pointer *p) {
    if (pointer) return;
    pointer = p;
    wl_pointer_add_listener(pointer, &pointer_listener, NULL);
}

void pointer_release(void) {
    if (!pointer) return;
    wl_pointer_release(pointer);
    pointer = NULL;
}

void register_on_mouse_enter (seat_mouse_enter  cb, void *user_data) { mouse_enter_cb  = cb; mouse_enter_userdata  = user_data; }
void register_on_mouse_leave (seat_mouse_leave  cb, void *user_data) { mouse_leave_cb  = cb; mouse_leave_userdata  = user_data; }
void register_on_mouse_motion(seat_mouse_motion cb, void *user_data) { mouse_motion_cb = cb; mouse_motion_userdata = user_data; }
void register_on_mouse_down  (seat_mouse_down   cb, void *user_data) { mouse_down_cb   = cb; mouse_down_userdata   = user_data; }
void register_on_mouse_up    (seat_mouse_up     cb, void *user_data) { mouse_up_cb     = cb; mouse_up_userdata     = user_data; }
void register_on_mouse_scroll(seat_mouse_scroll cb, void *user_data) { mouse_scroll_cb = cb; mouse_scroll_userdata = user_data; }
