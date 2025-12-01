#ifndef SEAT_H
#define SEAT_H

#include <wayland-client.h>
#include <stdint.h>
#include <stdbool.h>    

typedef struct {
    double mouse_x;
    double mouse_y;
    uint32_t mouse_buttons;
} dk_mouse_info;

typedef void (*seat_mouse_enter)(void* user_data);
typedef void (*seat_mouse_leave)(void* user_data);
typedef void (*seat_mouse_down)(void* user_data);
typedef void (*seat_mouse_up)(void* user_data);
typedef void (*seat_mouse_motion)(double x, double y, void* user_data);

typedef void (*seat_key_down)(uint32_t key, void* user_data);
typedef void (*seat_key_up)(uint32_t key, void* user_data);

void register_on_mouse_enter(seat_mouse_enter cb, void* user_data);
void register_on_mouse_leave(seat_mouse_leave cb, void* user_data);
void register_on_mouse_down(seat_mouse_down cb, void* user_data);
void register_on_mouse_up(seat_mouse_up cb, void* user_data);
void register_on_mouse_motion(seat_mouse_motion cb, void* user_data);
void register_on_key_down(seat_key_down cb, void* user_data);
void register_on_key_up(seat_key_up cb, void* user_data);

void seat_init();
void seat_cleanup();
void set_grab_keyboard(bool value);
struct wl_seat *get_wl_seat();

dk_mouse_info *seat_mouse_info();


#endif