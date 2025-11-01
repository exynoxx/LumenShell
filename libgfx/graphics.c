#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <EGL/egl.h>
#include "graphics.h"

static const char* default_vert_src =
    #include "shaders/default/vert.glsl"
    "";

static const char* default_frag_src =
    #include "shaders/default/frag.glsl"
    "";

static GLuint default_program = 0;
static GLuint rounded_rect_program = 0;
static GLuint texture_program = 0;

// Helper function to compile shader
static GLuint compile_shader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    
    GLint success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        char log[512];
        glGetShaderInfoLog(shader, 512, NULL, log);
        fprintf(stderr, "Shader compilation failed: %s\n", log);
        return 0;
    }
    
    return shader;
}

// Helper function to create shader program
static GLuint create_program(const char *vs_source, const char *fs_source) {
    GLuint vs = compile_shader(GL_VERTEX_SHADER, vs_source);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, fs_source);
    
    if (!vs || !fs) return 0;
    
    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    
    GLint success;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success) {
        char log[512];
        glGetProgramInfoLog(program, 512, NULL, log);
        fprintf(stderr, "Program linking failed: %s\n", log);
        return 0;
    }
    
    glDeleteShader(vs);
    glDeleteShader(fs);
    
    return program;
}

// Create orthographic projection matrix
static void create_ortho_matrix(float *mat, float left, float right, float bottom, float top) {
    memset(mat, 0, 16 * sizeof(float));
    mat[0] = 2.0f / (right - left);
    mat[5] = 2.0f / (top - bottom);
    mat[10] = -1.0f;
    mat[12] = -(right + left) / (right - left);
    mat[13] = -(top + bottom) / (top - bottom);
    mat[15] = 1.0f;
}

bool g2d_init(g2d_context *ctx, int screen_width, int screen_height) {
    ctx->screen_width = screen_width;
    ctx->screen_height = screen_height;
    ctx->current_color.r = 1.0f;
    ctx->current_color.g = 1.0f;
    ctx->current_color.b = 1.0f;
    ctx->current_color.a = 1.0f;
    
    // Create shader programs
    default_program = create_program(default_vert_src, default_frag_src);
    //rounded_rect_program = create_program(rounded_rect_vertex_shader, rounded_rect_fragment_shader);
    //texture_program = create_program(texture_vertex_shader, texture_fragment_shader);
    
    if (!default_program/*  || !rounded_rect_program || !texture_program */) {
        fprintf(stderr, "Failed to create shader programs\n");
        return false;
    }
    
    ctx->shader_program = default_program;
    //ctx->rounded_rect_program = rounded_rect_program;
    //ctx->texture_program = texture_program;
    
    // Create VBO
    glGenBuffers(1, &ctx->vbo);
    
    // Enable blending
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    return true;
}

void g2d_cleanup(g2d_context *ctx) {
    glDeleteBuffers(1, &ctx->vbo);
    if (default_program) glDeleteProgram(default_program);
    if (rounded_rect_program) glDeleteProgram(rounded_rect_program);
    if (texture_program) glDeleteProgram(texture_program);
}

void g2d_set_color(g2d_context *ctx, float r, float g, float b, float a) {
    ctx->current_color.r = r;
    ctx->current_color.g = g;
    ctx->current_color.b = b;
    ctx->current_color.a = a;
}

void g2d_begin_frame(g2d_context *ctx) {
    glViewport(0, 0, ctx->screen_width, ctx->screen_height);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
}

void g2d_end_frame() {
    glFlush();
}

void g2d_draw_rect(g2d_context *ctx, float x, float y, float width, float height) {
    glUseProgram(default_program);
    
    // Create projection matrix
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(default_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    // Set color
    GLint color_loc = glGetUniformLocation(default_program, "color");
    glUniform4f(color_loc, ctx->current_color.r, ctx->current_color.g, 
                ctx->current_color.b, ctx->current_color.a);
    
    // Create rectangle vertices
    float vertices[] = {
        x, y,
        x + width, y,
        x + width, y + height,
        x, y,
        x + width, y + height,
        x, y + height
    };
    
    glBindBuffer(GL_ARRAY_BUFFER, ctx->vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
    
    GLint pos_loc = glGetAttribLocation(default_program, "position");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(pos_loc);
}

void g2d_draw_rounded_rect(g2d_context *ctx, float x, float y, float width, float height, float radius) {
    glUseProgram(rounded_rect_program);
    
    // Create projection matrix
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(rounded_rect_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    // Set color
    GLint color_loc = glGetUniformLocation(rounded_rect_program, "color");
    glUniform4f(color_loc, ctx->current_color.r, ctx->current_color.g, 
                ctx->current_color.b, ctx->current_color.a);
    
    // Set rectangle parameters
    GLint rect_loc = glGetUniformLocation(rounded_rect_program, "rect");
    glUniform4f(rect_loc, x, y, width, height);
    
    // Set radius
    GLint radius_loc = glGetUniformLocation(rounded_rect_program, "radius");
    glUniform1f(radius_loc, radius);
    
    // Create simple quad that covers the entire rounded rectangle area
    float vertices[] = {
        x, y,
        x + width, y,
        x + width, y + height,
        x, y,
        x + width, y + height,
        x, y + height
    };
    
    glBindBuffer(GL_ARRAY_BUFFER, ctx->vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
    
    GLint pos_loc = glGetAttribLocation(rounded_rect_program, "position");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(pos_loc);
}

bool g2d_load_texture(g2d_texture *tex, const unsigned char *data, int width, int height, int channels) {
    glGenTextures(1, &tex->id);
    glBindTexture(GL_TEXTURE_2D, tex->id);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    GLenum format = (channels == 4) ? GL_RGBA : GL_RGB;
    glTexImage2D(GL_TEXTURE_2D, 0, format, width, height, 0, format, GL_UNSIGNED_BYTE, data);
    
    tex->width = width;
    tex->height = height;
    
    return true;
}

void g2d_draw_texture(g2d_context *ctx, g2d_texture *tex, float x, float y, float width, float height) {
    glUseProgram(texture_program);
    
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(texture_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    GLint color_loc = glGetUniformLocation(texture_program, "color");
    glUniform4f(color_loc, ctx->current_color.r, ctx->current_color.g, 
                ctx->current_color.b, ctx->current_color.a);
    
    float vertices[] = {
        x, y, 0.0f, 0.0f,
        x + width, y, 1.0f, 0.0f,
        x + width, y + height, 1.0f, 1.0f,
        x, y, 0.0f, 0.0f,
        x + width, y + height, 1.0f, 1.0f,
        x, y + height, 0.0f, 1.0f
    };
    
    glBindBuffer(GL_ARRAY_BUFFER, ctx->vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
    
    GLint pos_loc = glGetAttribLocation(texture_program, "position");
    GLint tex_loc = glGetAttribLocation(texture_program, "texCoord");
    
    glEnableVertexAttribArray(pos_loc);
    glEnableVertexAttribArray(tex_loc);
    
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0);
    glVertexAttribPointer(tex_loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float)));
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex->id);
    glUniform1i(glGetUniformLocation(texture_program, "texture0"), 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    
    glDisableVertexAttribArray(pos_loc);
    glDisableVertexAttribArray(tex_loc);
}

void g2d_free_texture(g2d_texture *tex) {
    glDeleteTextures(1, &tex->id);
    tex->id = 0;
}


