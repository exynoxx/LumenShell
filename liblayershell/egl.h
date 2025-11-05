#ifndef EGL_H
#define EGL_H

#include <stdlib.h>
#include <EGL/egl.h>
#include <wayland-egl.h>
#include <wayland-client.h>

static EGLDisplay egl_display = EGL_NO_DISPLAY;
static EGLSurface egl_surface = EGL_NO_SURFACE;
static EGLContext egl_context = EGL_NO_CONTEXT;
static struct wl_egl_window *egl_window = NULL;

void egl_init(struct wl_display *display, struct wl_surface *surface, int width, int height);
void egl_cleanup();

EGLDisplay get_egl_display();
EGLSurface get_egl_surface();
EGLContext get_egl_context();

#endif