#ifndef LIB_LAYER_SHELL_H
#define LIB_LAYER_SHELL_H

#include <EGL/egl.h>
#include <wayland-client.h>

#include "egl.h"
#include "wayland_features/compositor.h"
#include "wayland_features/layershell.h"
#include "wayland_features/seat.h"
#include "wayland_features/toplevel.h"

struct wl_display *display;

int init_layer_shell(const char *layer_name, int width, int height, Anchor anchor, bool exclusive_zone);
void destroy_layer_shell();
struct wl_display *get_wl_display();

#endif // LIB_LAYER_SHELL_H
