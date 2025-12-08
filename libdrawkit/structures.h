#ifndef STRUCTURES_H
#define STRUCTURES_H

#include <GLES2/gl2.h>
#include <stdbool.h>

#define MAX_UI_ELEMENTS 4096

typedef struct {
    float r, g, b, a;
} dk_color;


typedef struct {
    GLuint rounded_rect_program;
    GLuint texture_program;
    GLuint text_program;
    GLuint font_atlas_tex;
    GLuint vbo, vao;
    int screen_width;
    int screen_height;
    dk_color background_color;
} dk_context;

dk_context *dk_init_default(int screen_width, int screen_height);
dk_context *dk_init(int screen_width, int screen_height, int p);
void dk_cleanup(dk_context *ctx);

#endif