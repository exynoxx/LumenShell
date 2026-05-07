#ifndef EGL_H
#define EGL_H

#include <stdlib.h>
#include <EGL/egl.h>
#include <wayland-egl.h>
#include <wayland-client.h>

extern EGLDisplay egl_display;
extern EGLSurface egl_surface;
extern EGLContext egl_context;
extern struct wl_egl_window *egl_window;

int  egl_init(struct wl_display *display, struct wl_surface *surface, int width, int height);
void egl_swap_buffers(void);
void egl_cleanup(void);

EGLDisplay get_egl_display(void);
EGLSurface get_egl_surface(void);
EGLContext get_egl_context(void);

#endif
