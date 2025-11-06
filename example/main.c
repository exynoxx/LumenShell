#include <stdbool.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#include "../liblayershell/liblayershell.h"

#include "../src/draw.h"
#include "../src/layout.h"
#include "../src/texture.h"

int main() {

    int width = 1920;  // typical screen width, adjust as needed
    int height = 50;

    init_layer_shell("panel", width, height, BOTTOM, true);
    dk_mouse_info *mouse_info = seat_mouse_info();
    toplevel_print_all();

    dk_context ctx;
    dk_init(&ctx, width, height);
    dk_set_bg_color(&ctx, (dk_color){0,0,0,0});

    const char *fedora = "/usr/share/icons/hicolor/32x32/apps/fedora-logo-icon.png";
    GLuint fedora_tex = dk_texture_upload(dk_image_load(fedora));

    dk_ui_manager ui;
    dk_ui_init(&ui, &ctx);

    // --- Render loop ---
    while (display_dispatch_blocking() != -1) {
        //printf("Mouse: %f, %f\n", mouse_info->mouse_x, mouse_info->mouse_y);
        dk_begin_frame(&ctx);
        
        dk_ui_start_box(&ui, 0, 0);
        dk_ui_box_set_gap(&ui, 10);
        dk_ui_box_float(&ui, FLOAT_LEFT);

        dk_ui_texture(&ui, fedora_tex, 32, 32);
        dk_ui_texture(&ui, fedora_tex, 32, 32);
        dk_ui_texture(&ui, fedora_tex, 32, 32);

        dk_ui_end_box(&ui);
        dk_end_frame();
        egl_swap_buffers();
    }

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}