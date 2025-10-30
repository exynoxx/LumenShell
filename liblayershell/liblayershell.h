#ifndef LIB_LAYER_SHELL_H
#define LIB_LAYER_SHELL_H

#include <EGL/egl.h>
#include <wayland-client.h>
#include <wayland-egl.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize Wayland layer shell and EGL
int init_layer_shell(const char *layer_name, int width, int height);

// Access EGL objects
EGLDisplay get_egl_display(void);
EGLSurface get_egl_surface(void);
EGLContext get_egl_context(void);

// Cleanup
void destroy_layer_shell(void);

#ifdef __cplusplus
}
#endif

#endif // LIB_LAYER_SHELL_H
