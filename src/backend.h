#ifndef BACKEND_H
#define BACKEND_H

#include <GLES2/gl2.h>
#include <stdbool.h>
#include "structures.h"

bool dk_backend_init(dk_context *ctx);
void dk_backend_cleanup(dk_context *ctx);

void dk_set_bg_color(dk_context *ctx, dk_color color);
void dk_draw_node(dk_context *ctx, dk_ui_node *node);
void dk_draw_rect(dk_context *ctx, int x, int y, int width, int height, dk_color color);
//void dk_draw_rounded_rect(dk_context *ctx, int x, int y, int width, int height, int radius);
void dk_draw_texture(dk_context *ctx, GLuint texture_id, int x, int y, int width, int height);

void dk_begin_frame(dk_context *ctx);
void dk_end_frame();

#endif