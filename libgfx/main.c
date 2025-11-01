#include <stdbool.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#include "liblayershell.h"
#include "graphics.h"

int main() {

    int width = 1920;  // typical screen width, adjust as needed
    int height = 100;

    init_layer_shell("panel", width, 100);
    EGLDisplay egl_display = get_egl_display();
    EGLSurface egl_surface = get_egl_surface();
    EGLContext egl_context = get_egl_context();
    struct wl_display *display = get_wl_display();

    g2d_context ctx;
    g2d_init(&ctx, width, height);

    // --- Render loop ---
    while (wl_display_dispatch(display) != -1) {
        g2d_begin_frame(&ctx);
        
        g2d_set_color(&ctx, 1.0f, 0.0f, 0.0f, 1.0f);
        g2d_draw_rect(&ctx, 500, 25, 200, 50);

        g2d_end_frame();
        eglSwapBuffers(egl_display, egl_surface);
    }

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}