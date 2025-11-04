#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <wayland-client.h>
#include <wayland-egl.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

static struct wl_display *display = NULL;
static struct wl_compositor *compositor = NULL;
static struct zwlr_layer_shell_v1 *layer_shell = NULL;
static struct wl_surface *surface = NULL;
static struct wl_egl_window *egl_window = NULL;
static EGLDisplay egl_display;
static EGLSurface egl_surface;
static EGLContext egl_context;

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
static void layer_surface_config(void *data,
                                           struct zwlr_layer_surface_v1 *surface,
                                           uint32_t serial,
                                           uint32_t width,
                                           uint32_t height) {
    // ACK configure
    zwlr_layer_surface_v1_ack_configure(surface, serial);

    if (egl_window) {
        // Resize EGL window to compositor-provided size
        wl_egl_window_resize(egl_window, width, height, 0, 0);
    }

    wl_surface_commit((struct wl_surface*)data);
}
static void layer_surface_closed(void *data,
                                        struct zwlr_layer_surface_v1 *surface) { }
static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_config,
    .closed = layer_surface_closed
};

static void wl_init(){
    display = wl_display_connect(NULL);
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor || !layer_shell) { fprintf(stderr,"Missing Wayland globals\n"); return; }

    surface = wl_compositor_create_surface(compositor);
}

static void layer_shell_init(){
    struct zwlr_layer_surface_v1 *layer_surface =
        zwlr_layer_shell_v1_get_layer_surface(layer_shell,
                                              surface,
                                              NULL,
                                              ZWLR_LAYER_SHELL_V1_LAYER_TOP,
                                              "triangle-panel");
    zwlr_layer_surface_v1_set_anchor(layer_surface,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_size(layer_surface, 400, 300);
    zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, 50);
    zwlr_layer_surface_v1_add_listener(layer_surface, &layer_surface_listener, surface);
    wl_surface_commit(surface);
}

static void egl_init (){
    egl_display = eglGetDisplay((EGLNativeDisplayType)display);
    eglInitialize(egl_display, NULL, NULL);
    EGLint cfg_attribs[] = {
        EGL_SURFACE_TYPE,EGL_WINDOW_BIT,
        EGL_RED_SIZE,8, EGL_GREEN_SIZE,8, EGL_BLUE_SIZE,8, EGL_ALPHA_SIZE,8,
        EGL_RENDERABLE_TYPE,EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    EGLConfig config; EGLint num_configs;
    eglChooseConfig(egl_display, cfg_attribs, &config,1,&num_configs);

    egl_window = wl_egl_window_create(surface, 400, 300);
    egl_surface = eglCreateWindowSurface(egl_display, config, (EGLNativeWindowType)egl_window, NULL);
    EGLint ctx_attribs[] = {EGL_CONTEXT_CLIENT_VERSION,2,EGL_NONE};
    egl_context = eglCreateContext(egl_display, config, EGL_NO_CONTEXT, ctx_attribs);
    eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
}

static void swap_buffers(){
    eglSwapBuffers(egl_display, egl_surface);
}

static int display_dispatch(){
    return wl_display_dispatch(display);
}

static void dispose(){
    eglDestroySurface(egl_display, egl_surface);
    eglDestroyContext(egl_display, egl_context);
    wl_egl_window_destroy(egl_window);
    //zwlr_layer_surface_v1_destroy(layer_surface);
    wl_surface_destroy(surface);
    wl_display_disconnect(display);
}
/* 
int main() {
    
    // --- Layer surface ---
    

    // --- EGL setup ---
    

    // --- OpenGL ---
    GLuint program = create_program();
    glUseProgram(program);
    GLfloat vertices[] = {0.0f,0.5f, -0.5f,-0.5f, 0.5f,-0.5f};
    GLuint pos_loc = glGetAttribLocation(program,"pos");
    glVertexAttribPointer(pos_loc,2,GL_FLOAT,GL_FALSE,0,vertices);
    glEnableVertexAttribArray(pos_loc);

    // --- Render loop ---
    while (wl_display_dispatch(display) != -1) {
        glClearColor(0.0,0.0,0.0,1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES,0,3);
        eglSwapBuffers(egl_display, egl_surface);
    }

    // --- Cleanup ---
    
    return 0;
} */
