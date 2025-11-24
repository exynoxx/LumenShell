#include "structures.h"
#include <stdlib.h>
#include <string.h>

extern bool dk_backend_init(dk_context *ctx);
extern void dk_backend_cleanup(dk_context *ctx);
extern void dk_set_bg_color(dk_context *ctx, dk_color color);

dk_context *dk_init(int screen_width, int screen_height) {
    dk_context *ctx = malloc(sizeof(dk_context));
    dk_set_bg_color(ctx, (dk_color){0,0,0,1});

    ctx->screen_width = screen_width;
    ctx->screen_height = screen_height;
    
    dk_backend_init(ctx);
    
    return ctx;
}

void dk_cleanup(dk_context *ctx) {
    dk_backend_cleanup(ctx);
}