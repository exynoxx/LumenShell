#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <stdint.h>

struct wl_keyboard;

typedef void (*seat_key_down)(uint32_t key, void *user_data);
typedef void (*seat_key_up)  (uint32_t key, void *user_data);

void keyboard_init(void);
void keyboard_attach(struct wl_keyboard *keyboard);
void keyboard_release(void);
void keyboard_cleanup(void);

void register_on_key_down(seat_key_down cb, void *user_data);
void register_on_key_up  (seat_key_up   cb, void *user_data);

#endif
