#ifndef TEXTURE_H
#define TEXTURE_H

#include <GLES2/gl2.h>

typedef struct {
    int width;
    int height;
    int channels;
    unsigned char *data;
} Image;

Image load_icon(const char *path);
GLuint dk_upload(Image image);
void dk_free_texture(GLuint id);

#endif