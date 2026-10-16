#ifndef SEAT_H
#define SEAT_H

struct wl_seat;

// Binds the first advertised wl_seat, nothing more: an external toolkit (GTK)
// owns pointer/keyboard dispatch. wlhooks exposes wl_seat only so
// foreign-toplevel activate() and ext-idle-notify have a seat to reference.
void seat_init(void);
struct wl_seat *get_wl_seat(void);

#endif
