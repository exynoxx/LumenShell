#include <stdbool.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#include "../liblayershell/liblayershell.h"

#include "../src/structures.h"
#include "../src/layout.h"
#include "../src/hover.h"
#include "../src/backend.h"
#include "../src/texture.h"

int main() {

    int width = 1920;  // typical screen width, adjust as needed
    int height = 60;

    init_layer_shell("panel", width, height, BOTTOM, true);
    dk_mouse_info *mouse_info = seat_mouse_info();
    toplevel_print_all();

    dk_context *ctx = dk_init(width, height);
    dk_set_bg_color(ctx, (dk_color){0,0,0,0});

    const char *icon_fedora = "/usr/share/icons/hicolor/32x32/apps/fedora-logo-icon.png";
    const char *icon_firefox = "/usr/share/icons/hicolor/32x32/apps/firefox.png";
    GLuint tex_fedora = dk_texture_upload(dk_image_load(icon_fedora));
    GLuint tex_firefox = dk_texture_upload(dk_image_load(icon_firefox));

    int padding = (50-32)/2;


    // --- Render loop ---
    while (display_dispatch_blocking() != -1) {
        //printf("Mouse: %f, %f\n", mouse_info->mouse_x, mouse_info->mouse_y);
        dk_begin_frame(ctx);

        dk_reset(ctx);
        dk_start_box(ctx, 0, 0);
            dk_box_float(ctx, FLOAT_NONE);

            dk_start_box(ctx, 0, 50);
                dk_box_float(ctx, FLOAT_LEFT);
                dk_box_set_gap(ctx, 32);

                dk_color box_normal = (dk_color){1,1,1,0};
                dk_ui_node *b1 = dk_rect(ctx, 50, 50, box_normal);
                dk_ui_node *b2 = dk_rect(ctx, 50, 50, box_normal);
                dk_ui_node *b3 = dk_rect(ctx, 50, 50, box_normal);

            dk_end_box(ctx);

            dk_start_box(ctx, 0, 50);
                dk_box_float(ctx, FLOAT_LEFT);
                dk_box_set_padding(ctx,padding,padding,padding,padding);
                dk_box_set_gap(ctx, 50);

                dk_texture(ctx, tex_fedora, 32, 32);
                dk_texture(ctx, tex_firefox, 32, 32);
                dk_texture(ctx, tex_fedora, 32, 32);
            dk_end_box(ctx);

        dk_end_box(ctx);

        float shade = 0.08f;
        dk_draw_rect(ctx, 0, 50, width, 10, (dk_color){shade,shade,shade,1});

        evaluate_positions(ctx->node_mngr.root, 0, 0);
        dk_hitbox_query(ctx, mouse_info->mouse_x, mouse_info->mouse_y);

        if(b1->hovered) b1->data.color.a = 1;
        if(b2->hovered) b2->data.color.a = 1;
        if(b3->hovered) b3->data.color.a = 1;

        dk_draw(ctx, 0, 0);
        dk_end_frame();
        egl_swap_buffers();
    }

    dk_texture_free(tex_firefox);
    dk_texture_free(tex_fedora);

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}