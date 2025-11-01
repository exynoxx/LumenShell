#ifndef TEXTURE_H
#define TEXTURE_H

#include <GLES2/gl2.h>

typedef struct {
    int width;
    int height;
    int channels;
    unsigned char *data;
} Image;

typedef struct {
    GLuint id;
    int width;
    int height;
} g2d_texture;


Image load_icon(const char *path);
GLuint Upload(Image image);


#endif