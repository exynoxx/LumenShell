#ifndef LAYOUT_H
#define LAYOUT_H

#include <stdbool.h>
#include "structures.h"

void dk_ui_reset(dk_context *ctx);
void dk_ui_start_box(dk_context *ctx, int width, int height);

void dk_ui_box_set_padding(dk_context *ctx, int top, int right, int bottom, int left);
void dk_ui_box_set_gap(dk_context *ctx, int gap);
void dk_ui_box_float(dk_context *ctx, dk_float_mode float_mode);

void dk_ui_end_box(dk_context *ctx);

dk_ui_node *dk_ui_rect(dk_context *ctx, int width, int height, dk_color color);
//void dk_ui_rounded_rect(dk_context *ctx, int width, int height, int radius);
dk_ui_node *dk_ui_texture(dk_context *ctx, GLuint texture_id, int width, int height);

void evaluate_positions(dk_ui_node *elem, float parent_x, float parent_y);
void dk_ui_draw(dk_context *ctx, int root_x, int root_y);

#endif