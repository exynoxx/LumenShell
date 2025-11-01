#include "gfx2d.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Vertex shader: converts pixel coords to NDC
static const char *vertex_src =
    "attribute vec2 pos;\n"
    "attribute vec4 col;\n"
    "varying vec4 v_col;\n"
    "uniform vec2 screen;\n"
    "void main() {\n"
    "  vec2 p = pos / screen * 2.0 - 1.0;\n"
    "  p.y = -p.y;\n"
    "  gl_Position = vec4(p,0.0,1.0);\n"
    "  v_col = col;\n"
    "}";

// Fragment shader: outputs color
static const char *frag_src =
    "precision mediump float;\n"
    "varying vec4 v_col;\n"
    "void main() { gl_FragColor = v_col; }\n";

typedef struct { float x,y,r,g,b,a; } vertex2d_t;

// Helper: compile shader
static GLuint compile_shader(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s,1,&src,NULL);
    glCompileShader(s);
    GLint ok; glGetShaderiv(s,GL_COMPILE_STATUS,&ok);
    if(!ok){ char buf[512]; glGetShaderInfoLog(s,512,NULL,buf); fprintf(stderr,"%s\n",buf); exit(1);}
    return s;
}

static GLuint create_program() {
    GLuint vs = compile_shader(GL_VERTEX_SHADER,vertex_src);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER,frag_src);
    GLuint prog = glCreateProgram();
    glAttachShader(prog,vs); glAttachShader(prog,fs);
    glLinkProgram(prog);
    GLint ok; glGetProgramiv(prog,GL_LINK_STATUS,&ok);
    if(!ok){ fprintf(stderr,"Program link failed\n"); exit(1);}
    glDeleteShader(vs); glDeleteShader(fs);
    return prog;
}

// Initialize context
void gfx2d_init(gfx2d_context_t *ctx, int width, int height) {
    ctx->screen_width = width;
    ctx->screen_height = height;
    ctx->program = create_program();

    ctx->max_vertices = 1024;
    ctx->vertex_buffer = malloc(sizeof(vertex2d_t)*ctx->max_vertices);
    ctx->vertex_count = 0;

    glGenBuffers(1,&ctx->vbo);
    glGenVertexArraysOES(1,&ctx->vao);

    glBindVertexArrayOES(ctx->vao);
    glBindBuffer(GL_ARRAY_BUFFER,ctx->vbo);

    GLint pos_loc = glGetAttribLocation(ctx->program,"pos");
    GLint col_loc = glGetAttribLocation(ctx->program,"col");

    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc,2,GL_FLOAT,GL_FALSE,sizeof(vertex2d_t),(void*)0);
    glEnableVertexAttribArray(col_loc);
    glVertexAttribPointer(col_loc,4,GL_FLOAT,GL_FALSE,sizeof(vertex2d_t),(void*)(2*sizeof(float)));

    glBindVertexArrayOES(0);
}

// Clear screen
void gfx2d_clear(gfx2d_context_t *ctx, color_t color) {
    glClearColor(color.r,color.g,color.b,color.a);
    glClear(GL_COLOR_BUFFER_BIT);
}

// Add rectangle to buffer
void gfx2d_draw_rect(gfx2d_context_t *ctx, float x, float y, float w, float h, color_t color) {
    if(ctx->vertex_count+6 >= ctx->max_vertices) return;
    vertex2d_t v[6] = {
        {x,y,color.r,color.g,color.b,color.a},
        {x+w,y,color.r,color.g,color.b,color.a},
        {x+w,y+h,color.r,color.g,color.b,color.a},
        {x,y,color.r,color.g,color.b,color.a},
        {x+w,y+h,color.r,color.g,color.b,color.a},
        {x,y+h,color.r,color.g,color.b,color.a}
    };
    memcpy(&ctx->vertex_buffer[ctx->vertex_count],v,sizeof(v));
    ctx->vertex_count += 6;
}

// Add triangle
void gfx2d_draw_triangle(gfx2d_context_t *ctx,
                         float x1,float y1,
                         float x2,float y2,
                         float x3,float y3,
                         color_t color) {
    if(ctx->vertex_count+3>=ctx->max_vertices) return;
    vertex2d_t v[3] = {
        {x1,y1,color.r,color.g,color.b,color.a},
        {x2,y2,color.r,color.g,color.b,color.a},
        {x3,y3,color.r,color.g,color.b,color.a}
    };
    memcpy(&ctx->vertex_buffer[ctx->vertex_count],v,sizeof(v));
    ctx->vertex_count+=3;
}

// Flush buffer
void gfx2d_flush(gfx2d_context_t *ctx) {
    if(ctx->vertex_count==0) return;
    glUseProgram(ctx->program);
    GLint screen_loc = glGetUniformLocation(ctx->program,"screen");
    glUniform2f(screen_loc,(float)ctx->screen_width,(float)ctx->screen_height);

    glBindVertexArrayOES(ctx->vao);
    glBindBuffer(GL_ARRAY_BUFFER,ctx->vbo);
    glBufferData(GL_ARRAY_BUFFER,sizeof(vertex2d_t)*ctx->vertex_count,ctx->vertex_buffer,GL_DYNAMIC_DRAW);
    glDrawArrays(GL_TRIANGLES,0,ctx->vertex_count);
    ctx->vertex_count = 0;
}

// Free memory
void gfx2d_destroy(gfx2d_context_t *ctx) {
    free(ctx->vertex_buffer);
    glDeleteBuffers(1,&ctx->vbo);
    glDeleteVertexArraysOES(1,&ctx->vao);
    glDeleteProgram(ctx->program);
}
