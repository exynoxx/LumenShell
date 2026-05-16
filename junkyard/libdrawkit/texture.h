#ifndef TEXTURE_H
#define TEXTURE_H

#include <GLES2/gl2.h>

typedef struct {
    int width;
    int height;
    int channels;
    unsigned char *data;
} Image;

Image dk_image_load(const char *path);
GLuint dk_texture_upload(Image image);
void dk_texture_free(GLuint id);

#endif