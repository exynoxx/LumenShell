#include <stdbool.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#include "liblayershell.h"
#include "../src/graphics.h"
#include "../src/texture.h"

int main() {

    int width = 1920;  // typical screen width, adjust as needed
    int height = 100;

    init_layer_shell("panel", width, 50);
    EGLDisplay egl_display = get_egl_display();
    EGLSurface egl_surface = get_egl_surface();
    EGLContext egl_context = get_egl_context();
    struct wl_display *display = get_wl_display();

    dk_context ctx;
    dk_init(&ctx, width, height);
    dk_set_bg_color(&ctx, 0.0f, 0.0f, 0.0f, 0.8f);

    const char *fedora = "/usr/share/icons/hicolor/32x32/apps/fedora-logo-icon.png";

    Image img = load_icon(fedora);
    GLuint icon_tex = dk_upload(img);
    
    // --- Render loop ---
    while (wl_display_dispatch(display) != -1) {
        dk_begin_frame(&ctx);
        
        dk_set_color(&ctx, 1.0f, 0.0f, 0.0f, 1.0f);
        dk_draw_rect(&ctx, 100, 0, 50, 50);

        dk_set_color(&ctx, 0.0f, 1.0f, 0.0f, 1.0f);
        dk_draw_rect(&ctx, 125, 25, 50, 50);

        dk_set_color(&ctx, 1.0f, 1.0f, 1.0f, 1.0f);
        dk_draw_texture(&ctx, icon_tex, 500, 25, 32, 32);
        
        dk_end_frame();
        eglSwapBuffers(egl_display, egl_surface);
    }

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}