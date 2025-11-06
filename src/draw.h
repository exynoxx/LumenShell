// graphics2d.h
#ifndef DRAW_H
#define DRAW_H

//h part
#include <GLES2/gl2.h>
#include <stdbool.h>

// Color structure
typedef struct {
    float r, g, b, a;
} dk_color;

// Vector2 structure
typedef struct {
    float x, y;
} dk_vec2;

// Context structure
typedef struct {
    GLuint shader_program;
    GLuint rounded_rect_program;
    GLuint texture_program;
    GLuint vbo, vao;
    int screen_width;
    int screen_height;
    dk_color background_color;
    dk_color current_color;
} dk_context;

// Initialize the graphics library
bool dk_init(dk_context *ctx, int screen_width, int screen_height);

// Cleanup
void dk_cleanup(dk_context *ctx);

// Set drawing color
void dk_set_color(dk_context *ctx, dk_color color);
void dk_set_bg_color(dk_context *ctx, dk_color color);

// Drawing functions
void dk_draw_rect(dk_context *ctx, int x, int y, int width, int height);
//void dk_draw_rounded_rect(dk_context *ctx, int x, int y, int width, int height, int radius);

// Texture functions
void dk_draw_texture(dk_context *ctx, GLuint texture_id, int x, int y, int width, int height);

// Begin/End frame
void dk_begin_frame(dk_context *ctx);
void dk_end_frame();

#endif // DRAW_H