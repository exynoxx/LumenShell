#include <stdbool.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <graphene-1.0/graphene.h>

#include "../liblayershell/liblayershell.h"

#include "../src/draw.h"
#include "../src/texture.h"

int main() {

    int width = 1920;  // typical screen width, adjust as needed
    int height = 50;

    init_layer_shell("panel", width, height, BOTTOM);
    EGLDisplay egl_display = get_egl_display();
    EGLSurface egl_surface = get_egl_surface();
    EGLContext egl_context = get_egl_context();
    struct wl_display *display = get_wl_display();

    // --- Graphene setup ---
    graphene_rect_t rect;
    graphene_rect_init(&rect, 0, 0, (float)width, (float)height);

    graphene_point_t center;
    graphene_rect_get_center(&rect, &center);
    printf("Rect center: %.2f, %.2f\n", center.x, center.y);

    // Translate the rectangle (example: move panel up slightly)
    graphene_point_t offset;
    graphene_point_init(&offset, 0, -5);
    graphene_rect_offset(&rect, offset.x, offset.y);

    // Convert rectangle to 4 vertices (OpenGL normalized coordinates)
    float left   = -1.0f;
    float right  =  1.0f;
    float top    =  1.0f - (2.0f * rect.origin.y / height);
    float bottom =  1.0f - (2.0f * (rect.origin.y + rect.size.height) / height);

    GLfloat vertices[] = {
        left,  bottom,
        right, bottom,
        left,  top,
        right, top,
    };

    // --- Simple shader ---
    const char *vert_src =
        "attribute vec2 pos;\n"
        "void main() {\n"
        "  gl_Position = vec4(pos, 0.0, 1.0);\n"
        "}";

    const char *frag_src =
        "precision mediump float;\n"
        "void main() {\n"
        "  gl_FragColor = vec4(0.0, 0.0, 0.0, 0.8);\n"  // semi-transparent black panel
        "}";

    GLuint vert = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vert, 1, &vert_src, NULL);
    glCompileShader(vert);

    GLuint frag = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(frag, 1, &frag_src, NULL);
    glCompileShader(frag);

    GLuint prog = glCreateProgram();
    glAttachShader(prog, vert);
    glAttachShader(prog, frag);
    glLinkProgram(prog);
    glUseProgram(prog);

    GLint attr_pos = glGetAttribLocation(prog, "pos");
    glEnableVertexAttribArray(attr_pos);
    glVertexAttribPointer(attr_pos, 2, GL_FLOAT, GL_FALSE, 0, vertices);

    // --- Main render loop ---
    while (wl_display_dispatch_pending(display) != -1) {
        glViewport(0, 0, width, height);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);

        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        eglSwapBuffers(egl_display, egl_surface);
    }

    return 0;
}