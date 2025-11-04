#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "liblayershell.h"
#include "egl.h"
#include "registry.h"

int init_layer_shell(const char *layer_name, int width, int height, EDGE edge) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { 
        fprintf(stderr,"Failed to connect to Wayland display\n"); 
        return -1; 
    }

    compositor_init();
    layer_shell_init();
    seat_init();

    registry_init(display);

    struct wl_surface *surface = layer_shell_create_surface(layer_name, width, height, edge);
    egl_init(display, surface, width, height);

    return 0;
}

/* void destroy_layer_shell(void) {
    if (egl_display != EGL_NO_DISPLAY) {
        eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (egl_surface != EGL_NO_SURFACE) eglDestroySurface(egl_display, egl_surface);
        if (egl_context != EGL_NO_CONTEXT) eglDestroyContext(egl_display, egl_context);
        eglTerminate(egl_display);
        egl_display = EGL_NO_DISPLAY;
        egl_surface = EGL_NO_SURFACE;
        egl_context = EGL_NO_CONTEXT;
    }

    if (egl_window) {
        wl_egl_window_destroy(egl_window);
        egl_window = NULL;
    }

    if (surface) { wl_surface_destroy(surface); surface = NULL; }
    if (layer_shell) { zwlr_layer_shell_v1_destroy(layer_shell); layer_shell = NULL; }
    if (compositor) { wl_compositor_destroy(compositor); compositor = NULL; }
    if (display) { wl_display_disconnect(display); display = NULL; }
}
 */