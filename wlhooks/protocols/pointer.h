#ifndef POINTER_H
#define POINTER_H

#include <stdint.h>

struct wl_pointer;

typedef void (*seat_mouse_enter)  (void *user_data);
typedef void (*seat_mouse_leave)  (void *user_data);
typedef void (*seat_mouse_down)   (uint32_t button, void *user_data);
typedef void (*seat_mouse_up)     (uint32_t button, void *user_data);
typedef void (*seat_mouse_motion) (int32_t x, int32_t y, void *user_data);
typedef void (*seat_mouse_scroll) (int32_t amount, void *user_data);

void pointer_attach(struct wl_pointer *pointer);
void pointer_release(void);

void register_on_mouse_enter (seat_mouse_enter  cb, void *user_data);
void register_on_mouse_leave (seat_mouse_leave  cb, void *user_data);
void register_on_mouse_down  (seat_mouse_down   cb, void *user_data);
void register_on_mouse_up    (seat_mouse_up     cb, void *user_data);
void register_on_mouse_motion(seat_mouse_motion cb, void *user_data);
void register_on_mouse_scroll(seat_mouse_scroll cb, void *user_data);

#endif
