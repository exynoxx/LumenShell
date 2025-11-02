#ifndef SEAT_H
#define SEAT_H

#include <wayland-client.h>
#include <stdint.h>

typedef struct {
    double mouse_x;
    double mouse_y;
    uint32_t mouse_buttons;
} dk_mouse_info;

void seat_init();
dk_mouse_info *seat_mouse_info();

#endif