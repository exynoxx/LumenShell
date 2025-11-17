#ifndef LAYOUT_H
#define LAYOUT_H

#include <stdbool.h>
#include "structures.h"

void dk_reset(dk_context *ctx);
void dk_start_box(dk_context *ctx, int width, int height, int x, int y);

void dk_box_set_padding(dk_context *ctx, int top, int right, int bottom, int left);
void dk_box_set_gap(dk_context *ctx, int gap);
void dk_box_float(dk_context *ctx, dk_float_mode float_mode);

void dk_end_box(dk_context *ctx);

dk_ui_node *dk_rect(dk_context *ctx, int width, int height, dk_color color);
//void dk_rounded_rect(dk_context *ctx, int width, int height, int radius);
dk_ui_node *dk_texture(dk_context *ctx, GLuint texture_id, int width, int height);

void evaluate_positions(dk_ui_node *elem, float parent_x, float parent_y);
void dk_draw(dk_context *ctx, int root_x, int root_y);

#endif