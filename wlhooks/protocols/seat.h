#ifndef SEAT_H
#define SEAT_H

#include <stdbool.h>
#include <stdint.h>

// Public mouse / keyboard callback registries live in pointer.h / keyboard.h
// but are pulled in here for backward-compatible single-include callers.
#include "pointer.h"
#include "keyboard.h"

struct wl_seat;

void seat_init(void);
void seat_cleanup(void);
void set_grab_keyboard(bool value);
bool seat_should_grab_keyboard(void);
struct wl_seat *get_wl_seat(void);

// The most recent input event serial (pointer enter/leave/button or keyboard
// enter/leave/key). Used by xdg_activation token requests. Updated by
// pointer.c / keyboard.c via seat_set_last_serial().
uint32_t seat_get_last_serial(void);
void     seat_set_last_serial(uint32_t serial);

#endif
