#ifndef GFX2D_H
#define GFX2D_H

#include <GLES2/gl2.h>

typedef struct { float r,g,b,a; } color_t;

typedef struct {
    int screen_width;
    int screen_height;

    GLuint program;
    GLuint vbo;
    GLuint vao;

    float *vertex_buffer;
    int vertex_count;
    int max_vertices;
} gfx2d_context_t;

// Initialize 2D graphics context
void gfx2d_init(gfx2d_context_t *ctx, int width, int height);

// Draw a rectangle at (x,y) with size w,h
void gfx2d_draw_rect(gfx2d_context_t *ctx, float x, float y, float w, float h, color_t color);

// Draw a triangle given 3 points
void gfx2d_draw_triangle(gfx2d_context_t *ctx,
                         float x1,float y1,
                         float x2,float y2,
                         float x3,float y3,
                         color_t color);

// Upload and draw all queued vertices
void gfx2d_flush(gfx2d_context_t *ctx);

// Clear the current frame
void gfx2d_clear(gfx2d_context_t *ctx, color_t color);

// Free memory
void gfx2d_destroy(gfx2d_context_t *ctx);

#endif
