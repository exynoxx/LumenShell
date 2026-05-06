#ifndef LIB_LAYER_SHELL_H
#define LIB_LAYER_SHELL_H

#include <EGL/egl.h>
#include <wayland-client.h>

#include "egl.h"
#include "protocols/compositor.h"
#include "protocols/layershell.h"
#include "protocols/seat.h"
#include "protocols/toplevel.h"
#include "protocols/screencopy.h"
#include "protocols/output.h"

extern struct wl_display *wl_display;

int wlhooks_init();
int init_layer_shell(const char *layer_name, int width, int height, Anchor anchor, bool exclusive_zone, int exclusive_zone_height);
void wlhooks_destroy(); //call layer_shell_destroy for layer shell only
void layer_shell_set_input_region(int x, int y, int w, int h);
struct wl_display *get_wl_display();
int display_dispatch_blocking();

#endif // LIB_LAYER_SHELL_H
