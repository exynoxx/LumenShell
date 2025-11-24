#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <EGL/egl.h>
#include "backend.h"

static const char* default_vert_src =
    #include "shaders/default/vert.glsl"
    "";

static const char* default_frag_src =
    #include "shaders/default/frag.glsl"
    "";

static const char* texture_vert_src =
    #include "shaders/texture/vert.glsl"
    "";

static const char* texture_frag_src =
    #include "shaders/texture/frag.glsl"
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

bool dk_backend_init(dk_context *ctx) {
    default_program = create_program(default_vert_src, default_frag_src);
    //rounded_rect_program = create_program(rounded_rect_vertex_shader, rounded_rect_fragment_shader);
    texture_program = create_program(texture_vert_src, texture_frag_src);
    
    if (!default_program || !texture_program /*  || !rounded_rect_program || !texture_program */) {
        fprintf(stderr, "Failed to create shader programs\n");
        return false;
    }
    
    ctx->shader_program = default_program;
    //ctx->rounded_rect_program = rounded_rect_program;
    ctx->texture_program = texture_program;
    
    // Create VBO
    glGenBuffers(1, &ctx->vbo);
    
    // Enable blending
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    return true;
}

void dk_backend_cleanup(dk_context *ctx) {
    glDeleteBuffers(1, &ctx->vbo);
    if (default_program) glDeleteProgram(default_program);
    if (rounded_rect_program) glDeleteProgram(rounded_rect_program);
    if (texture_program) glDeleteProgram(texture_program);
}

void dk_set_bg_color(dk_context *ctx, dk_color color) {
    ctx->background_color.r = color.r;
    ctx->background_color.g = color.g;
    ctx->background_color.b = color.b;
    ctx->background_color.a = color.a;
}

void dk_begin_frame(dk_context *ctx) {
    glViewport(0, 0, ctx->screen_width, ctx->screen_height);
    glClearColor(ctx->background_color.r, ctx->background_color.g, ctx->background_color.b, ctx->background_color.a);
    glClear(GL_COLOR_BUFFER_BIT);
}

void dk_end_frame() {
    glFlush();
}

void dk_draw_rect(dk_context *ctx, int x, int y, int width, int height, dk_color color) {
    glUseProgram(default_program);
    
    // Create projection matrix
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(default_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    // Set color
    GLint color_loc = glGetUniformLocation(default_program, "color");
    glUniform4f(color_loc, color.r, color.g, 
                color.b, color.a);
    
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

/* void dk_draw_rounded_rect(dk_context *ctx, float x, float y, float width, float height, float radius) {
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
} */


void dk_draw_texture(dk_context *ctx, GLuint texture_id, int x, int y, int width, int height) {
    //printf("draw_text %d %d %d %d",x,y,width,height);

    glUseProgram(texture_program);
    
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(texture_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    GLint color_loc = glGetUniformLocation(texture_program, "color");
    glUniform4f(color_loc, 1,1,1,1);
    
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
    glBindTexture(GL_TEXTURE_2D, texture_id);
    glUniform1i(glGetUniformLocation(texture_program, "texture0"), 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    
    glDisableVertexAttribArray(pos_loc);
    glDisableVertexAttribArray(tex_loc);
}


