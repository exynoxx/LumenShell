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
#include "protocols/activation.h"

extern struct wl_display *wl_display;

int  wlhooks_init(void);
void wlhooks_destroy(void); // call layer_shell_destroy for layer shell only
struct wl_display *get_wl_display(void);
int  display_dispatch_blocking(void);

#endif // LIB_LAYER_SHELL_H
