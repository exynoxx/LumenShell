#ifndef LIB_LAYER_SHELL_H
#define LIB_LAYER_SHELL_H

#include <EGL/egl.h>
#include <wayland-client.h>

#include "egl.h"
#include "protocols/compositor.h"
#include "protocols/layershell.h"
#include "protocols/seat.h"
#include "protocols/toplevel.h"

extern struct wl_display *wl_display;

int init_layer_shell(const char *layer_name, int width, int height, Anchor anchor, bool exclusive_zone);
void destroy_layer_shell();
struct wl_display *get_wl_display();
int display_dispatch_blocking();

#endif // LIB_LAYER_SHELL_H
