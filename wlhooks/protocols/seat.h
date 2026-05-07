#ifndef SEAT_H
#define SEAT_H

#include <wayland-client.h>
#include <stdint.h>
#include <stdbool.h>    

typedef void (*seat_mouse_enter)(void* user_data);
typedef void (*seat_mouse_leave)(void* user_data);
typedef void (*seat_mouse_down)(uint32_t button, void* user_data);
typedef void (*seat_mouse_up)(uint32_t button, void* user_data);
typedef void (*seat_mouse_motion)(int32_t x, int32_t y, void* user_data);
typedef void (*seat_mouse_scroll)(int32_t amount, void* user_data);

typedef void (*seat_key_down)(uint32_t key, void* user_data);
typedef void (*seat_key_up)(uint32_t key, void* user_data);

void register_on_mouse_enter(seat_mouse_enter cb, void* user_data);
void register_on_mouse_leave(seat_mouse_leave cb, void* user_data);
void register_on_mouse_down(seat_mouse_down cb, void* user_data);
void register_on_mouse_up(seat_mouse_up cb, void* user_data);
void register_on_mouse_motion(seat_mouse_motion cb, void* user_data);
void register_on_mouse_scroll(seat_mouse_scroll cb, void* user_data);
void register_on_key_down(seat_key_down cb, void* user_data);
void register_on_key_up(seat_key_up cb, void* user_data);

void seat_init();
void seat_cleanup();
void set_grab_keyboard(bool value);
struct wl_seat *get_wl_seat();
uint32_t seat_get_last_serial(void);

#endif