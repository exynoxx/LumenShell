#include "keyboard.h"
#include "seat.h"
#include "xkb.h"

#include <unistd.h>
#include <wayland-client.h>

static struct wl_keyboard *keyboard = NULL;

static seat_key_down key_down_cb; static void *key_down_userdata = NULL;
static seat_key_up   key_up_cb;   static void *key_up_userdata   = NULL;

static void on_keymap(void *data, struct wl_keyboard *kb,
                      uint32_t format, int32_t fd, uint32_t size) {
    if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        close(fd);
        return;
    }
    xkb_load_keymap_from_fd(fd, size);
    close(fd);
}

static void on_enter(void *data, struct wl_keyboard *kb,
                     uint32_t serial, struct wl_surface *surface,
                     struct wl_array *keys) {
    seat_set_last_serial(serial);
}

static void on_leave(void *data, struct wl_keyboard *kb,
                     uint32_t serial, struct wl_surface *surface) {
    seat_set_last_serial(serial);
}

static void on_key(void *data, struct wl_keyboard *kb,
                   uint32_t serial, uint32_t time, uint32_t keycode,
                   uint32_t state_w) {
    seat_set_last_serial(serial);

    uint32_t keysym = xkb_translate_keycode(keycode);
    if (keysym == 0) return;

    if (state_w == WL_KEYBOARD_KEY_STATE_PRESSED) {
        if (key_down_cb) key_down_cb(keysym, key_down_userdata);
    } else {
        if (key_up_cb) key_up_cb(keysym, key_up_userdata);
    }
}

static void on_modifiers(void *data, struct wl_keyboard *kb,
                         uint32_t serial, uint32_t mods_depressed,
                         uint32_t mods_latched, uint32_t mods_locked,
                         uint32_t group) {
    xkb_update_modifiers(mods_depressed, mods_latched, mods_locked, group);
}

static void on_repeat_info(void *data, struct wl_keyboard *kb,
                           int32_t rate, int32_t delay) {}

static const struct wl_keyboard_listener keyboard_listener = {
    .keymap      = on_keymap,
    .enter       = on_enter,
    .leave       = on_leave,
    .key         = on_key,
    .modifiers   = on_modifiers,
    .repeat_info = on_repeat_info,
};

void keyboard_init(void) {
    xkb_module_init();
}

void keyboard_attach(struct wl_keyboard *kb) {
    if (keyboard) return;
    keyboard = kb;
    wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL);
}

void keyboard_release(void) {
    if (!keyboard) return;
    wl_keyboard_release(keyboard);
    keyboard = NULL;
}

void keyboard_cleanup(void) {
    keyboard_release();
    xkb_module_cleanup();
}

void register_on_key_down(seat_key_down cb, void *user_data) { key_down_cb = cb; key_down_userdata = user_data; }
void register_on_key_up  (seat_key_up   cb, void *user_data) { key_up_cb   = cb; key_up_userdata   = user_data; }
