#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <EGL/egl.h>
#include "backend.h"
#include "shaders.h"
#include "font.h"

//font.h
extern Glyph glyphs[NUM_CHARS];
extern int base_px_height;
static float identity[16];
static float ortho[16];


void dk_populate_projections(GLuint program, dk_context *ctx);

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
static void create_identity_matrix(float *mat) {
    memset(mat, 0, 16 * sizeof(float));

    mat[0]  = 1.0f;
    mat[5]  = 1.0f;
    mat[10] = 1.0f;
    mat[15] = 1.0f;
}

bool dk_backend_init_default(dk_context *ctx) {
    return dk_backend_init(ctx, 1);
}

bool dk_backend_init(dk_context *ctx, int groups) {  

    printf("init with group count %d\n", groups);
    ctx->num_projections = groups+1;

    init_shaders(ctx, ctx->num_projections);
    create_identity_matrix(identity);
    create_ortho_matrix(ortho, 0, ctx->screen_width, ctx->screen_height, 0);

    ctx->tex_color = (dk_color){1,1,1,1};

    ctx->active[0] = true;
    ctx->dirty[0] = true;
    memcpy(ctx->projections[0], ortho, 16*sizeof(float));
    for(int i = 1; i < ctx->num_projections;i++) {
        ctx->active[i] = false;
        ctx->dirty[i] = true;
        memcpy(ctx->projections[i], identity, 16*sizeof(float));
    }

    // Create VBO
    glGenBuffers(1, &ctx->vbo);
    
    // Enable blending
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    dk_font_init(ctx);
    return true;
}

void dk_backend_cleanup(dk_context *ctx) {
    glDeleteBuffers(1, &ctx->vbo);
    if (ctx->shapes_program) glDeleteProgram(ctx->shapes_program);
    if (ctx->texture_program) glDeleteProgram(ctx->texture_program);
}

void dk_set_bg_color(dk_context *ctx, dk_color color) {
    ctx->background_color.r = color.r;
    ctx->background_color.g = color.g;
    ctx->background_color.b = color.b;
    ctx->background_color.a = color.a;
}

void dk_set_tex_color(dk_context *ctx, dk_color color){
    ctx->tex_color.r = color.r;
    ctx->tex_color.g = color.g;
    ctx->tex_color.b = color.b;
    ctx->tex_color.a = color.a;
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
    glUseProgram(ctx->shapes_program);

    GLint mode_loc = glGetUniformLocation(ctx->shapes_program, "mode");
    glUniform1i(mode_loc, 0);
    
    dk_populate_projections(ctx->shapes_program, ctx);

    // Set color
    GLint color_loc = glGetUniformLocation(ctx->shapes_program, "color");
    glUniform4f(color_loc, color.r, color.g, color.b, color.a);
    
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
    
    GLint pos_loc = glGetAttribLocation(ctx->shapes_program, "position");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(pos_loc);
}

void dk_draw_rect_rounded(dk_context *ctx, float x, float y, float width, float height, float radius, dk_color color) {
    glUseProgram(ctx->shapes_program);

    GLint mode_loc = glGetUniformLocation(ctx->shapes_program, "mode");
    glUniform1i(mode_loc, 1);
    
    dk_populate_projections(ctx->shapes_program, ctx);

    GLint color_loc = glGetUniformLocation(ctx->shapes_program, "color");
    glUniform4f(color_loc, color.r, color.g, color.b, color.a);
    
    GLint rect_loc = glGetUniformLocation(ctx->shapes_program, "rect");
    glUniform4f(rect_loc, x, y, width, height);
    
    GLint radius_loc = glGetUniformLocation(ctx->shapes_program, "radius");
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
    
    GLint pos_loc = glGetAttribLocation(ctx->shapes_program, "position");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(pos_loc);
}

void dk_draw_circle(dk_context *ctx, int cx, int cy, int radius, dk_color color) {
    glUseProgram(ctx->shapes_program);

    GLint mode_loc = glGetUniformLocation(ctx->shapes_program, "mode");
    glUniform1i(mode_loc, 2);

    dk_populate_projections(ctx->shapes_program, ctx);

    GLint color_loc = glGetUniformLocation(ctx->shapes_program, "color");
    glUniform4f(color_loc, color.r, color.g, color.b, color.a);

    // --- Rectangle covering the circle ---
    // In the shader, rect.xy + rect.zw * 0.5 = center
    float x = cx - radius;
    float y = cy - radius;
    float w = radius * 2.0f;
    float h = radius * 2.0f;

    GLint rect_loc = glGetUniformLocation(ctx->shapes_program, "rect");
    glUniform4f(rect_loc, x, y, w, h);

    // --- Radius uniform ---
    GLint radius_loc = glGetUniformLocation(ctx->shapes_program, "radius");
    glUniform1f(radius_loc, radius);

    // --- Create quad vertices ---
    float vertices[] = {
        x,     y,
        x + w, y,
        x + w, y + h,
        x,     y,
        x + w, y + h,
        x,     y + h
    };

    glBindBuffer(GL_ARRAY_BUFFER, ctx->vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);

    GLint pos_loc = glGetAttribLocation(ctx->shapes_program, "position");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, 0);

    // --- Draw ---
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(pos_loc);
}


void dk_draw_texture(dk_context *ctx, GLuint texture_id, int x, int y, int width, int height) {
    //printf("draw_text %d %d %d %d",x,y,width,height);

    glUseProgram(ctx->texture_program);

    GLint mode_loc = glGetUniformLocation(ctx->texture_program, "mode");
    glUniform1i(mode_loc, 0);
    
    dk_populate_projections(ctx->shapes_program, ctx);
    
    GLint color_loc = glGetUniformLocation(ctx->texture_program, "color");
    glUniform4f(color_loc, ctx->tex_color.r, ctx->tex_color.g, ctx->tex_color.b, ctx->tex_color.a);
    
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
    
    GLint pos_loc = glGetAttribLocation(ctx->texture_program, "position");
    GLint tex_loc = glGetAttribLocation(ctx->texture_program, "texCoord");
    
    glEnableVertexAttribArray(pos_loc);
    glEnableVertexAttribArray(tex_loc);
    
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0);
    glVertexAttribPointer(tex_loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float)));
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture_id);
    glUniform1i(glGetUniformLocation(ctx->texture_program, "texture0"), 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    
    glDisableVertexAttribArray(pos_loc);
    glDisableVertexAttribArray(tex_loc);
}

//closely related to font.h
void dk_draw_text(dk_context *ctx, const char *text, int x, int y, float font_size, dk_color color) {
    if (!ctx->font_atlas_tex || !text) return;

    glUseProgram(ctx->texture_program);
    
    // Cache uniform locations (do this ONCE, ideally at initialization)
    static GLint mode_loc = -1;
    static GLint color_loc = -1;
    static GLint pos_loc = -1;
    static GLint texCoord_loc = -1;
    static GLint texture_loc = -1;
    
    if (mode_loc == -1) {
        mode_loc = glGetUniformLocation(ctx->texture_program, "mode");
        color_loc = glGetUniformLocation(ctx->texture_program, "color");
        pos_loc = glGetAttribLocation(ctx->texture_program, "position");
        texCoord_loc = glGetAttribLocation(ctx->texture_program, "texCoord");
        texture_loc = glGetUniformLocation(ctx->texture_program, "texture0");
    }

    glUniform1i(mode_loc, 1);
    dk_populate_projections(ctx->texture_program, ctx);
    glUniform4f(color_loc, color.r, color.g, color.b, color.a);
    
    // Bind texture ONCE
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, ctx->font_atlas_tex);
    glUniform1i(texture_loc, 0);

    float scale = font_size / (float)base_px_height;
    size_t len = strlen(text);
    int total_w = dk_width_of(ctx, text, font_size);
    int pen_x = x - (total_w / 2);
    int pen_y = y;

    // Pre-allocate vertex buffer for ALL characters
    size_t max_vertices = len * 6 * 4; // 6 vertices, 4 floats each
    float *all_vertices = (float*)malloc(max_vertices * sizeof(float));
    size_t vertex_count = 0;

    // Build ALL vertices in CPU memory
    for (size_t i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)text[i];
        if (c < FIRST_CHAR || c > LAST_CHAR) continue;

        Glyph *g = &glyphs[c - FIRST_CHAR];
        float gw = g->bw * scale;
        float gh = g->bh * scale;
        float x0 = pen_x + g->bl * scale;
        float y0 = pen_y - g->bt * scale;
        float x1 = x0 + gw;
        float y1 = y0 + gh;
        float u0 = g->tx0, v0 = g->ty0;
        float u1 = g->tx1, v1 = g->ty1;

        // Triangle 1
        all_vertices[vertex_count++] = x0; all_vertices[vertex_count++] = y0;
        all_vertices[vertex_count++] = u0; all_vertices[vertex_count++] = v0;
        
        all_vertices[vertex_count++] = x1; all_vertices[vertex_count++] = y0;
        all_vertices[vertex_count++] = u1; all_vertices[vertex_count++] = v0;
        
        all_vertices[vertex_count++] = x1; all_vertices[vertex_count++] = y1;
        all_vertices[vertex_count++] = u1; all_vertices[vertex_count++] = v1;

        // Triangle 2
        all_vertices[vertex_count++] = x0; all_vertices[vertex_count++] = y0;
        all_vertices[vertex_count++] = u0; all_vertices[vertex_count++] = v0;
        
        all_vertices[vertex_count++] = x1; all_vertices[vertex_count++] = y1;
        all_vertices[vertex_count++] = u1; all_vertices[vertex_count++] = v1;
        
        all_vertices[vertex_count++] = x0; all_vertices[vertex_count++] = y1;
        all_vertices[vertex_count++] = u0; all_vertices[vertex_count++] = v1;

        pen_x += g->ax * scale;
    }

    // Upload ALL vertices in ONE buffer operation
    glBindBuffer(GL_ARRAY_BUFFER, ctx->vbo);
    glBufferData(GL_ARRAY_BUFFER, vertex_count * sizeof(float), all_vertices, GL_DYNAMIC_DRAW);
    
    glEnableVertexAttribArray(pos_loc);
    glEnableVertexAttribArray(texCoord_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 4*sizeof(float), (void*)0);
    glVertexAttribPointer(texCoord_loc, 2, GL_FLOAT, GL_FALSE, 4*sizeof(float), (void*)(2*sizeof(float)));

    // ONE draw call for entire string
    glDrawArrays(GL_TRIANGLES, 0, vertex_count / 4);

    glDisableVertexAttribArray(pos_loc);
    glDisableVertexAttribArray(texCoord_loc);
    
    free(all_vertices);
}

void dk_stencil_push(dk_context *ctx){
    glEnable(GL_STENCIL_TEST);
    glClear(GL_STENCIL_BUFFER_BIT);
    glStencilMask(0xFF);

    glStencilFunc(GL_ALWAYS, 1, 0xFF);
    glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);

    glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
}

void dk_stencil_apply(dk_context *ctx) {
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

    glStencilFunc(GL_EQUAL, 1, 0xFF);
    glStencilMask(0x00);
}

void dk_stencil_pop(dk_context *ctx){
    glDisable(GL_STENCIL_TEST);
}

void dk_populate_projections(GLuint program, dk_context *ctx){
    GLint proj_loc = glGetUniformLocation(program, "projections");
    for(int i = 0; i < ctx->num_projections; i++) {

        //TODO does not work
        //if(!dirty[i]) continue;

        float *mat = (ctx->active[i]) ? ctx->projections[i] : identity;
        glUniformMatrix4fv(proj_loc+i, 1, GL_FALSE, mat);
        ctx->dirty[i] = false;
    }
}

void dk_begin_group(dk_context *ctx, int group){
    if (group == 0 || group >= ctx->num_projections) {
        printf("group out of bouds");
        return;
    }

    ctx->active[group] = true;
    ctx->dirty[group] = true;
}

void dk_end_group(dk_context *ctx, int group){
    if (group == 0 || group >= ctx->num_projections) {
        printf("group out of bouds");
        return;
    }

    ctx->active[group] = false;
    ctx->dirty[group] = true;
}


void dk_group_matrix(dk_context *ctx, int group, float* mat){
    if (group == 0 || group >= ctx->num_projections) {
        printf("group out of bouds");
        return;
    }

    ctx->dirty[group] = true;
    memcpy(ctx->projections[group], mat, 16*sizeof(float));
}