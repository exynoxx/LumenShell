#include "texture.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

Image dk_image_load(const char *path) {
    int width, height, channels;
    unsigned char *data = stbi_load(path, &width, &height, &channels, 0);
    
    if (!data) {
        fprintf(stderr, "Failed to load icon: %s\n", path);
        fprintf(stderr, "Reason: %s\n", stbi_failure_reason());
    }
    
    printf("✓ Loaded: %s\n", path);
    printf("  Size: %dx%d, Channels: %d\n", width, height, channels);
    
    //bool success = g2d_load_texture(tex, data, width, height, channels);
    //stbi_image_free(data);
    Image ret = {
        width = width,  
        height = height,
        channels = channels,
        data = data
    };

    return ret;
}

GLuint dk_texture_upload(Image image){
    GLuint id;

    glGenTextures(1, &id);
    glBindTexture(GL_TEXTURE_2D, id);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    GLenum format = (image.channels == 4) ? GL_RGBA : GL_RGB;
    glTexImage2D(GL_TEXTURE_2D, 0, format, image.width, image.height, 0, format, GL_UNSIGNED_BYTE, image.data);

    return id;
}

void dk_texture_free(GLuint id) {
    glDeleteTextures(1, &id);
}