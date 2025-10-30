#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "liblayershell.h"
#include "wayland/wlr-layer-shell-unstable-v1-client-protocol.h"

// --- Wayland globals ---
static struct wl_compositor *compositor = NULL;
static struct zwlr_layer_shell_v1 *layer_shell = NULL;
static struct wl_surface *surface = NULL;
static struct wl_egl_window *egl_window = NULL;

// --- EGL globals ---
static EGLDisplay egl_display = EGL_NO_DISPLAY;
static EGLSurface egl_surface = EGL_NO_SURFACE;
static EGLContext egl_context = EGL_NO_CONTEXT;

// --- Registry listener ---
static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, "wl_compositor") == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (strcmp(interface, "zwlr_layer_shell_v1") == 0)
        layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) { }
static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_remove
};

// --- Layer surface listener ---
static void layer_surface_handle_configure(void *data,
                                           struct zwlr_layer_surface_v1 *surface,
                                           uint32_t serial,
                                           uint32_t width,
                                           uint32_t height) {
    zwlr_layer_surface_v1_ack_configure(surface, serial);
    if (egl_window) {
        wl_egl_window_resize(egl_window, width, height, 0, 0);
    }
    wl_surface_commit((struct wl_surface*)data);
}
static void layer_surface_handle_closed(void *data,
                                        struct zwlr_layer_surface_v1 *surface) { }
static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_handle_configure,
    .closed = layer_surface_handle_closed
};

// --- Wayland display ---
static struct wl_display *display = NULL;

int init_layer_shell(const char *layer_name, int width, int height) {
    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr,"Failed to connect to Wayland display\n"); return -1; }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor || !layer_shell) {
        fprintf(stderr,"Missing Wayland globals\n");
        return -1;
    }

    // Create surface
    surface = wl_compositor_create_surface(compositor);
    struct zwlr_layer_surface_v1 *layer_surface =
        zwlr_layer_shell_v1_get_layer_surface(layer_shell,
                                              surface,
                                              NULL,
                                              ZWLR_LAYER_SHELL_V1_LAYER_TOP,
                                              layer_name);
    zwlr_layer_surface_v1_set_anchor(layer_surface,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_size(layer_surface, width, height);
    zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, 50);
    zwlr_layer_surface_v1_add_listener(layer_surface, &layer_surface_listener, surface);
    wl_surface_commit(surface);

    // --- EGL setup ---
    egl_display = eglGetDisplay((EGLNativeDisplayType)display);
    if (egl_display == EGL_NO_DISPLAY) { fprintf(stderr,"Failed to get EGL display\n"); return -1; }
    eglInitialize(egl_display, NULL, NULL);

    EGLint cfg_attribs[] = {
        EGL_SURFACE_TYPE,EGL_WINDOW_BIT,
        EGL_RED_SIZE,8, EGL_GREEN_SIZE,8, EGL_BLUE_SIZE,8, EGL_ALPHA_SIZE,8,
        EGL_RENDERABLE_TYPE,EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    EGLConfig config; EGLint num_configs;
    if (!eglChooseConfig(egl_display, cfg_attribs, &config,1,&num_configs) || num_configs < 1) {
        fprintf(stderr,"Failed to choose EGL config\n"); return -1;
    }

    egl_window = wl_egl_window_create(surface, width, height);
    egl_surface = eglCreateWindowSurface(egl_display, config, (EGLNativeWindowType)egl_window, NULL);
    EGLint ctx_attribs[] = {EGL_CONTEXT_CLIENT_VERSION,2,EGL_NONE};
    egl_context = eglCreateContext(egl_display, config, EGL_NO_CONTEXT, ctx_attribs);

    if (!eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context)) {
        fprintf(stderr,"Failed to make EGL context current\n"); return -1;
    }

    return 0;
}

EGLDisplay get_egl_display(void) { return egl_display; }
EGLSurface get_egl_surface(void) { return egl_surface; }
EGLContext get_egl_context(void) { return egl_context; }

void destroy_layer_shell(void) {
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
