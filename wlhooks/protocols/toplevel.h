#ifndef TOPLEVEL_H
#define TOPLEVEL_H

#include <stdlib.h>
#include <stdbool.h>
#include "../generated/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

typedef void (*toplevel_window_new)(uint32_t id, const char* app_id, const char* title, void* user_data);
typedef void (*toplevel_window_rm)(uint32_t id, void* user_data);
typedef void (*toplevel_window_focus)(uint32_t id, void* user_data);
typedef void (*toplevel_window_output)(uint32_t id, const char* output_name, bool entered, void* user_data);

void toplevel_init(void);
void toplevel_cleanup(void);
void register_on_window_new(toplevel_window_new cb, void* user_data);
void register_on_window_rm(toplevel_window_rm cb, void* user_data);
void register_on_window_focus(toplevel_window_focus cb, void* user_data);
void register_on_window_output_changed(toplevel_window_output cb, void* user_data);

void toplevel_activate_by_id(uint32_t id);
void toplevel_minimize_by_id(uint32_t id);
void toplevel_close_by_id(uint32_t id);

// Report the on-screen rectangle (taskbar button) for a window, in the
// coordinate space of `surface`, as the compositor's minimize-animation hint.
// No-op (with a warning) if the active backend can't express it.
void toplevel_set_rectangle_by_id(uint32_t id, struct wl_surface *surface,
                                  int32_t x, int32_t y, int32_t width, int32_t height);

#endif