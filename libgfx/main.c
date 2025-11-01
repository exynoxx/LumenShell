#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <wayland-client.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include "liblayershell.h"

const char *vertex_src =
    "attribute vec2 pos;\n"
    "void main() { gl_Position = vec4(pos, 0.0, 1.0); }";
const char *frag_src =
    "void main() { gl_FragColor = vec4(1.0, 0.5, 0.0, 1.0); }";

GLuint compile_shader(GLenum type, const char *src) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, NULL);
    glCompileShader(shader);
    GLint ok; glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) { char buf[512]; glGetShaderInfoLog(shader,512,NULL,buf); fprintf(stderr,"%s\n",buf); exit(1);}
    return shader;
}
GLuint create_program() {
    GLuint v = compile_shader(GL_VERTEX_SHADER, vertex_src);
    GLuint f = compile_shader(GL_FRAGMENT_SHADER, frag_src);
    GLuint prog = glCreateProgram();
    glAttachShader(prog,v); glAttachShader(prog,f); glLinkProgram(prog);
    GLint ok; glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if(!ok){ fprintf(stderr,"Program link failed\n"); exit(1);}
    glDeleteShader(v); glDeleteShader(f);
    return prog;
}

int main() {
   
    init_layer_shell("panel", 800,100);
    EGLDisplay egl_display = get_egl_display();
    EGLSurface egl_surface = get_egl_surface();
    EGLContext egl_context = get_egl_context(); 
    struct wl_display *display = get_wl_display();

    // --- OpenGL ---
    GLuint program = create_program();
    glUseProgram(program);
    GLfloat vertices[] = {0.0f,0.5f, -0.5f,-0.5f, 0.5f,-0.5f};
    GLuint pos_loc = glGetAttribLocation(program,"pos");
    glVertexAttribPointer(pos_loc,2,GL_FLOAT,GL_FALSE,0,vertices);
    glEnableVertexAttribArray(pos_loc);

    // --- Render loop ---
    while (wl_display_dispatch(display) != -1) {
        glClearColor(0.0,0.0,0.0,1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES,0,3);
        eglSwapBuffers(egl_display, egl_surface);
    }

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}
