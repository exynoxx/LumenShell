#ifndef LIB_LAYER_SHELL_H
#define LIB_LAYER_SHELL_H

#include <EGL/egl.h>
#include <wayland-client.h>

#include "wayland_modules/compositor.h"
#include "wayland_modules/layershell.h"
#include "wayland_modules/seat.h"

int init_layer_shell(const char *layer_name, int width, int height, EDGE edge);

#endif // LIB_LAYER_SHELL_H
