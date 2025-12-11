#include "seat.h"
#include "registry.h"
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>
#include <wayland-client.h>

static struct wl_seat *seat = NULL;
struct wl_keyboard *keyboard;
struct wl_pointer *pointer;

static dk_mouse_info mouse_info = {0};
struct xkb_context *xkb_context;
struct xkb_keymap *xkb_keymap;
struct xkb_state *xkb_state;
static bool grab_keyboard = false;

static seat_mouse_enter mouse_enter_cb;
static void *mouse_enter_userdata = NULL;

static seat_mouse_leave mouse_leave_cb;
static void *mouse_leave_userdata = NULL;

static seat_mouse_motion mouse_motion_cb;
static void *mouse_motion_userdata = NULL;

static seat_mouse_down mouse_down_cb;
static void *mouse_down_userdata = NULL;

static seat_mouse_up mouse_up_cb;
static void *mouse_up_userdata = NULL;

static seat_key_down key_down_cb;
static void *key_down_userdata = NULL;

static seat_key_up key_up_cb;
static void *key_up_userdata = NULL;

/* ### POINTER ### */

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
    if(mouse_motion_cb){
        mouse_motion_cb(info->mouse_x, info->mouse_y, mouse_motion_userdata);
    }
}

static void pointer_button(void *data, struct wl_pointer *pointer,
                          uint32_t serial, uint32_t time, uint32_t button,
                          uint32_t state) {
    dk_mouse_info *info = data;
    if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
        info->mouse_buttons |= (1 << button);
        if(mouse_down_cb){
            mouse_down_cb(mouse_down_userdata);
        }
    } else {
        info->mouse_buttons &= ~(1 << button);
        if(mouse_up_cb){
            mouse_up_cb(mouse_up_userdata);
        }
    }
}

void pointer_axis(void *data, struct wl_pointer *wl_pointer, uint32_t time, uint32_t axis, wl_fixed_t value) {
    // Scroll events - can be empty for now
}

void pointer_frame(void *data, struct wl_pointer *wl_pointer) {
    // Frame complete - can be empty
}

static void pointer_axis_source(void *data, struct wl_pointer *wl_pointer, uint32_t source) {
    // empty
}

static void pointer_axis_discrete(void *data, struct wl_pointer *wl_pointer, uint32_t axis, int32_t discrete) {
    // empty
}

static void axis_stop(void *data,struct wl_pointer *wl_pointer,uint32_t time,uint32_t axis){
    // empty
}
static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter,
    .leave = pointer_leave,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = pointer_axis,
    .frame = pointer_frame,
    .axis_source = pointer_axis_source,
    .axis_discrete = pointer_axis_discrete,
    .axis_stop = axis_stop
};

/* ### KEYBOARD ### */

// Keyboard event handlers
static void keyboard_keymap(void *data, struct wl_keyboard *keyboard,
                           uint32_t format, int32_t fd, uint32_t size) {
    struct app_state *state = data;
    
    if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        close(fd);
        return;
    }
    
    char *map_shm = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
    if (map_shm == MAP_FAILED) {
        close(fd);
        return;
    }
    
    xkb_keymap = xkb_keymap_new_from_string(xkb_context, map_shm, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
    
    munmap(map_shm, size);
    close(fd);
    
    xkb_state = xkb_state_new(xkb_keymap);
}

static void keyboard_enter(void *data, struct wl_keyboard *keyboard,
                          uint32_t serial, struct wl_surface *surface,
                          struct wl_array *keys) {
}

static void keyboard_leave(void *data, struct wl_keyboard *keyboard,
                          uint32_t serial, struct wl_surface *surface) {
}

static void keyboard_key(void *data, struct wl_keyboard *keyboard,
                        uint32_t serial, uint32_t time, uint32_t key,
                        uint32_t state_w) {
    struct app_state *state = data;
    
    xkb_keysym_t keysym = xkb_state_key_get_one_sym(xkb_state, key + 8);
    if (state_w == WL_KEYBOARD_KEY_STATE_PRESSED) {
        if(key_down_cb) key_down_cb(keysym, key_down_userdata);
    } else {
        if(key_up_cb) key_up_cb(keysym, key_up_userdata);
    }
}

static void keyboard_modifiers(void *data, struct wl_keyboard *keyboard,
                              uint32_t serial, uint32_t mods_depressed,
                              uint32_t mods_latched, uint32_t mods_locked,
                              uint32_t group) {
    struct app_state *state = data;
    xkb_state_update_mask(xkb_state, mods_depressed, mods_latched, mods_locked, 0, 0, group);
}

static void repeat_info(void *data, struct wl_keyboard *wl_keyboard,int32_t rate, int32_t delay){

}

static const struct wl_keyboard_listener keyboard_listener = {
    .keymap = keyboard_keymap,
    .enter = keyboard_enter,
    .leave = keyboard_leave,
    .key = keyboard_key,
    .modifiers = keyboard_modifiers,
    .repeat_info = repeat_info
};


static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t capabilities) {
    if (capabilities & WL_SEAT_CAPABILITY_POINTER) {
        pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer, &pointer_listener, data);
    }

    if (capabilities & WL_SEAT_CAPABILITY_KEYBOARD && grab_keyboard) {
        keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(keyboard, &keyboard_listener, data);
    }
}

static void seat_name(void *data, struct wl_seat *seat, const char *name) {}

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
    xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    registry_add_handler(wl_seat_interface.name, seat_registry_handler, NULL);
}

void seat_cleanup(void){
    xkb_state_unref(xkb_state);
    xkb_keymap_unref(xkb_keymap);
    xkb_context_unref(xkb_context);

    wl_keyboard_release(keyboard);
    wl_pointer_release(pointer);
    wl_seat_release(seat);
}

void set_grab_keyboard(bool value){
    grab_keyboard = value;
}

struct wl_seat *get_wl_seat(){
    return seat;
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

void register_on_mouse_motion(seat_mouse_motion cb, void* user_data){
    mouse_motion_cb = cb;
    mouse_motion_userdata = user_data;
}

void register_on_mouse_down(seat_mouse_down cb, void* user_data){
    mouse_down_cb = cb;
    mouse_down_userdata = user_data;
}

void register_on_mouse_up(seat_mouse_up cb, void* user_data){
    mouse_up_cb = cb;
    mouse_up_userdata = user_data;
}

void register_on_key_down(seat_key_down cb, void* user_data){
    key_down_cb = cb;
    key_down_userdata = user_data;
}

void register_on_key_up(seat_key_up cb, void* user_data){
    key_up_cb = cb;
    key_up_userdata = user_data;
}
