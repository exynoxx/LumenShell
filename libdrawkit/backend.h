#ifndef BACKEND_H
#define BACKEND_H

#include <GLES2/gl2.h>
#include <stdbool.h>
#include "structures.h"

bool dk_backend_init_default(dk_context *ctx);
bool dk_backend_init(dk_context *ctx, int projection_count);

void dk_backend_cleanup(dk_context *ctx);

void dk_set_bg_color(dk_context *ctx, dk_color color);
void dk_draw_rect(dk_context *ctx, int x, int y, int width, int height, dk_color color);
void dk_draw_rect_rounded(dk_context *ctx, float x, float y, float width, float height, float radius, dk_color color);
void dk_draw_circle(dk_context *ctx, int cx, int cy, int radius, dk_color color);

void dk_draw_texture(dk_context *ctx, GLuint texture_id, int x, int y, int width, int height);

int dk_width_of(dk_context *ctx, const char *text, float font_size);
int dk_height_of(dk_context *ctx, const char *text, float font_size);
void dk_draw_text(dk_context *ctx, const char *text, int x, int y, float font_size);

void dk_begin_group(int group);
void dk_end_group(int group);
void dk_group_location(int group, int x, int y);
void dk_group_matrix(int group, float* mat);

void dk_begin_frame(dk_context *ctx);
void dk_end_frame();

#endif