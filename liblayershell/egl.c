#include "egl.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <wayland-egl.h>
#include <wayland-client.h>

void egl_init(struct wl_display *display, struct wl_surface *surface, int width, int height){

    egl_display = eglGetDisplay((EGLNativeDisplayType)display);
    if (egl_display == EGL_NO_DISPLAY) { fprintf(stderr,"Failed to get EGL display\n"); return; }
    eglInitialize(egl_display, NULL, NULL);

    EGLint cfg_attribs[] = {
        EGL_SURFACE_TYPE,EGL_WINDOW_BIT,
        EGL_RED_SIZE,8, EGL_GREEN_SIZE,8, EGL_BLUE_SIZE,8, EGL_ALPHA_SIZE,8,
        EGL_RENDERABLE_TYPE,EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };

    EGLConfig config; 
    EGLint num_configs;
    if (!eglChooseConfig(egl_display, cfg_attribs, &config,1,&num_configs) || num_configs < 1) {
        fprintf(stderr,"Failed to choose EGL config\n"); return;
    }

    egl_window = wl_egl_window_create(surface, width, height);
    egl_surface = eglCreateWindowSurface(egl_display, config, (EGLNativeWindowType)egl_window, NULL);
    EGLint ctx_attribs[] = {EGL_CONTEXT_CLIENT_VERSION,2,EGL_NONE};
    egl_context = eglCreateContext(egl_display, config, EGL_NO_CONTEXT, ctx_attribs);

    if (!eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context)) {
        fprintf(stderr,"Failed to make EGL context current\n"); return;
    }
}

EGLDisplay get_egl_display() { return egl_display; }
EGLSurface get_egl_surface() { return egl_surface; }
EGLContext get_egl_context() { return egl_context; }