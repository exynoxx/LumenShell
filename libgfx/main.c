#include <stdbool.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#include "liblayershell.h"
#include "graphics.h"

#include "texture.h"

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

    const char *fedora = "/usr/share/icons/hicolor/48x48/apps/fedora-logo-icon.png";

    Image img = load_icon(fedora);
    GLuint icon_tex = Upload(img);
    
    // --- Render loop ---
    while (wl_display_dispatch(display) != -1) {
        g2d_begin_frame(&ctx);
        
        // Draw icon at original size
        g2d_set_color(&ctx, 1.0f, 1.0f, 1.0f, 1.0f);
        g2d_draw_texture(&ctx, icon_tex, 100, 0, img.width, img.height);
        
        // Draw icon scaled 2x
        g2d_draw_texture(&ctx, icon_tex, 300, 0, img.width * 2, img.height * 2);
        
        // Draw icon scaled 3x
        g2d_draw_texture(&ctx, icon_tex, 550, 0, img.width * 3, img.height * 3);
        
        g2d_end_frame();
        eglSwapBuffers(egl_display, egl_surface);
    }

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}