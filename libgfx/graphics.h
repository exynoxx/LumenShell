// graphics2d.h
#ifndef GRAPHICS2D_H
#define GRAPHICS2D_H

//h part
#include <GLES2/gl2.h>
#include <stdbool.h>

// Color structure
typedef struct {
    float r, g, b, a;
} g2d_color;

// Vector2 structure
typedef struct {
    float x, y;
} g2d_vec2;

// Context structure
typedef struct {
    GLuint shader_program;
    GLuint rounded_rect_program;
    GLuint texture_program;
    GLuint vbo, vao;
    int screen_width;
    int screen_height;
    g2d_color current_color;
} g2d_context;

// Initialize the graphics library
bool g2d_init(g2d_context *ctx, int screen_width, int screen_height);

// Cleanup
void g2d_cleanup(g2d_context *ctx);

// Set drawing color
void g2d_set_color(g2d_context *ctx, float r, float g, float b, float a);

// Drawing functions
void g2d_draw_rect(g2d_context *ctx, float x, float y, float width, float height);
void g2d_draw_rounded_rect(g2d_context *ctx, float x, float y, float width, float height, float radius);

// Texture functions
void g2d_draw_texture(g2d_context *ctx, GLuint texture_id, float x, float y, float width, float height);

// Begin/End frame
void g2d_begin_frame(g2d_context *ctx);
void g2d_end_frame();

#endif // GRAPHICS2D_H