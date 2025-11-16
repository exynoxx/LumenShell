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

void seat_init();
dk_mouse_info *seat_mouse_info();
void register_on_mouse_enter(seat_mouse_enter cb, void* user_data);
void register_on_mouse_leave(seat_mouse_leave cb, void* user_data);


#endif