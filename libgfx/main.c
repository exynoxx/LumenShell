#include <wayland-client.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <math.h>
#include "liblayershell.h"
#include <stdio.h>
#include <stdlib.h>

const char *vertex_src =
    "attribute vec2 pos;\n"
    "varying vec2 uv;\n"
    "void main() {\n"
    "  gl_Position = vec4(pos, 0.0, 1.0);\n"
    "  uv = pos * 0.5 + 0.5;\n"
    "}";

const char *frag_src =
    "precision mediump float;\n"
    "varying vec2 uv;\n"
    "uniform vec2 resolution;\n"
    "float rounded_rect(vec2 p, vec2 center, vec2 size, float radius) {\n"
    "  vec2 d = abs(p - center) - size + radius;\n"
    "  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;\n"
    "}\n"
    "void main() {\n"
    "  vec2 p = uv * resolution;\n"
    "  vec2 center = resolution * 0.5;\n"
    "  vec2 size = vec2(100.0, 30.0);\n"
    "  float radius = 10.0;\n"
    "  float dist = rounded_rect(p, center, size, radius);\n"
    "  float alpha = smoothstep(2.0, -2.0, dist);\n"
    "  vec3 color = mix(vec3(0.0), vec3(0.0, 0.8, 1.0), alpha);\n"
    "  gl_FragColor = vec4(color, alpha * 0.9);\n"
    "}";

GLuint compile_shader(GLenum type, const char *src) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, NULL);
    glCompileShader(shader);
    GLint ok;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char buf[512];
        glGetShaderInfoLog(shader, 512, NULL, buf);
        fprintf(stderr, "%s\n", buf);
        exit(1);
    }
    return shader;
}

GLuint create_program() {
    GLuint v = compile_shader(GL_VERTEX_SHADER, vertex_src);
    GLuint f = compile_shader(GL_FRAGMENT_SHADER, frag_src);
    GLuint prog = glCreateProgram();
    glAttachShader(prog, v);
    glAttachShader(prog, f);
    glLinkProgram(prog);
    GLint ok;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        fprintf(stderr, "Program link failed\n");
        exit(1);
    }
    glDeleteShader(v);
    glDeleteShader(f);
    return prog;
}

int main() {

    int width = 1920;  // typical screen width, adjust as needed
    int height = 100;

    init_layer_shell("panel", width, 100);
    EGLDisplay egl_display = get_egl_display();
    EGLSurface egl_surface = get_egl_surface();
    EGLContext egl_context = get_egl_context();
    struct wl_display *display = get_wl_display();

    // --- OpenGL ---
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    GLuint program = create_program();
    glUseProgram(program);

    // Full-screen quad
    GLfloat vertices[] = {
        -1.0f, 1.0f,   // top-left
        -1.0f, -1.0f,  // bottom-left
        1.0f, -1.0f,   // bottom-right
        1.0f, 1.0f     // top-right
    };

    GLuint indices[] = {0, 1, 2, 2, 3, 0};

    GLuint pos_loc = glGetAttribLocation(program, "pos");
    GLint res_loc = glGetUniformLocation(program, "resolution");

    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, vertices);
    glEnableVertexAttribArray(pos_loc);
    glUniform2f(res_loc, (float)width, (float)height);

    // --- Render loop ---
    while (wl_display_dispatch(display) != -1) {
        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, indices);

        eglSwapBuffers(egl_display, egl_surface);
    }

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}