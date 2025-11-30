#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <EGL/egl.h>
#include "backend.h"
#include <ft2build.h>
#include FT_FREETYPE_H  // this defines FT_Library, FT_Face, etc.

typedef struct {
    float ax, ay; // advance.x, advance.y (pixels)
    int bw, bh;   // bitmap width, height (pixels)
    int bl, bt;   // bitmap left, bitmap top (bearing)
    float tx0, ty0, tx1, ty1; // texture coords in atlas
} Glyph;

#define FIRST_CHAR 32
#define LAST_CHAR 126
#define NUM_CHARS (LAST_CHAR - FIRST_CHAR + 1)

static Glyph glyphs[NUM_CHARS];
static int atlas_w = 0, atlas_h = 0;
static int base_px_height = 48; // rasterization baseline used to build atlas

static const char* default_vert_src =
    #include "shaders/default/vert.glsl"
    "";

static const char* default_frag_src =
    #include "shaders/default/frag.glsl"
    "";

static const char* rounded_frag_src =
    #include "shaders/rounded/frag.glsl"
    "";

static const char* rounded_vert_src =
    #include "shaders/rounded/vert.glsl"
    "";

static const char* texture_vert_src =
    #include "shaders/texture/vert.glsl"
    "";

static const char* texture_frag_src =
    #include "shaders/texture/frag.glsl"
    "";

static const char* text_vert_src =
    #include "shaders/text/vert.glsl"
    "";

static const char* text_frag_src =
    #include "shaders/text/frag.glsl"
    "";

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
    ctx->shader_program = create_program(default_vert_src, default_frag_src);
    ctx->rounded_rect_program = create_program(rounded_vert_src, rounded_frag_src);
    ctx->texture_program = create_program(texture_vert_src, texture_frag_src);
    ctx->text_program = create_program(text_vert_src, text_frag_src);
    
    if (!ctx->shader_program || !ctx->rounded_rect_program  || !ctx->texture_program || !ctx->text_program) {
        fprintf(stderr, "Failed to create shader programs\n");
        return false;
    }

    // Create VBO
    glGenBuffers(1, &ctx->vbo);
    
    // Enable blending
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    FT_Library ft;
    if (FT_Init_FreeType(&ft)) {
        fprintf(stderr, "Failed to init FreeType\n");
        return false;
    }

    FT_Face face;
    const char *font_path = "/home/nicholas/.local/share/fonts/panels/droid_sans.ttf"; // example
    base_px_height = 32; // rasterization baseline

    if (FT_New_Face(ft, font_path, 0, &face)) {
        fprintf(stderr, "Failed to load font: %s\n", font_path);
        FT_Done_FreeType(ft);
        return false;
    }

    FT_Set_Pixel_Sizes(face, 0, base_px_height);

    // Compute simple atlas size: one row of ASCII glyphs
    int atlas_w = 0, atlas_h = 0;
    for (int c = FIRST_CHAR; c <= LAST_CHAR; c++) {
        if (FT_Load_Char(face, c, FT_LOAD_RENDER)) continue;
        atlas_w += face->glyph->bitmap.width + 1; // 1px spacing
        if (face->glyph->bitmap.rows > atlas_h) atlas_h = face->glyph->bitmap.rows;
    }

    if (atlas_w == 0 || atlas_h == 0) {
        fprintf(stderr, "No glyphs found\n");
        FT_Done_Face(face);
        FT_Done_FreeType(ft);
        return false;
    }

    // Create atlas texture
    glGenTextures(1, &ctx->font_atlas_tex);
    glBindTexture(GL_TEXTURE_2D, ctx->font_atlas_tex);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_LUMINANCE,
        atlas_w,
        atlas_h,
        0,
        GL_LUMINANCE,
        GL_UNSIGNED_BYTE,
        NULL
    );

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // upload glyphs
    int x = 0;
    for (int c = FIRST_CHAR; c <= LAST_CHAR; c++) {
        if (FT_Load_Char(face, c, FT_LOAD_RENDER)) continue;
        FT_GlyphSlot g = face->glyph;

        glTexSubImage2D(
            GL_TEXTURE_2D,
            0,
            x, 0,
            g->bitmap.width,
            g->bitmap.rows,
            GL_LUMINANCE,
            GL_UNSIGNED_BYTE,
            g->bitmap.buffer
        );

        Glyph *gg = &glyphs[c - FIRST_CHAR];
        gg->ax = g->advance.x / 64.0f;
        gg->ay = g->advance.y / 64.0f;
        gg->bw = g->bitmap.width;
        gg->bh = g->bitmap.rows;
        gg->bl = g->bitmap_left;
        gg->bt = g->bitmap_top;

        gg->tx0 = (float)x / atlas_w;
        gg->ty0 = 0.0f;
        gg->tx1 = (float)(x + g->bitmap.width) / atlas_w;
        gg->ty1 = (float)g->bitmap.rows / atlas_h;

        x += g->bitmap.width + 1;
    }


    FT_Done_Face(face);
    FT_Done_FreeType(ft);
    
    return true;
}

void dk_backend_cleanup(dk_context *ctx) {
    glDeleteBuffers(1, &ctx->vbo);
    if (ctx->shader_program) glDeleteProgram(ctx->shader_program);
    if (ctx->rounded_rect_program) glDeleteProgram(ctx->rounded_rect_program);
    if (ctx->texture_program) glDeleteProgram(ctx->texture_program);
    if (ctx->text_program) glDeleteProgram(ctx->text_program);
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
    glUseProgram(ctx->shader_program);
    
    // Create projection matrix
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(ctx->shader_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    // Set color
    GLint color_loc = glGetUniformLocation(ctx->shader_program, "color");
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
    
    GLint pos_loc = glGetAttribLocation(ctx->shader_program, "position");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(pos_loc);
}

void dk_draw_rect_rounded(dk_context *ctx, float x, float y, float width, float height, float radius, dk_color color) {
    glUseProgram(ctx->rounded_rect_program);
    
    // Create projection matrix
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(ctx->rounded_rect_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    GLint color_loc = glGetUniformLocation(ctx->rounded_rect_program, "color");
    glUniform4f(color_loc, color.r, color.g, color.b, color.a);
    
    GLint rect_loc = glGetUniformLocation(ctx->rounded_rect_program, "rect");
    glUniform4f(rect_loc, x, y, width, height);
    
    GLint radius_loc = glGetUniformLocation(ctx->rounded_rect_program, "radius");
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
    
    GLint pos_loc = glGetAttribLocation(ctx->rounded_rect_program, "position");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(pos_loc);
}


void dk_draw_texture(dk_context *ctx, GLuint texture_id, int x, int y, int width, int height) {
    //printf("draw_text %d %d %d %d",x,y,width,height);

    glUseProgram(ctx->texture_program);
    
    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    
    GLint proj_loc = glGetUniformLocation(ctx->texture_program, "projection");
    glUniformMatrix4fv(proj_loc, 1, GL_FALSE, proj);
    
    GLint color_loc = glGetUniformLocation(ctx->texture_program, "color");
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

void dk_draw_text(dk_context *ctx, const char *text, int x, int y, float font_size) {
    if (!ctx->font_atlas_tex) return;
    if (!text) return;

    glUseProgram(ctx->text_program);

    float proj[16];
    create_ortho_matrix(proj, 0, ctx->screen_width, ctx->screen_height, 0);
    glUniformMatrix4fv(glGetUniformLocation(ctx->text_program, "u_proj"), 1, GL_FALSE, proj);

    glUniform4f(glGetUniformLocation(ctx->text_program, "u_color"), 1,1,1,1);

    glBindBuffer(GL_ARRAY_BUFFER, ctx->vbo);

    int pen_x = x;
    int pen_y = y;

    size_t len = strlen(text);

    for (size_t i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)text[i];
        if (c < FIRST_CHAR || c > LAST_CHAR) continue;

        Glyph *g = &glyphs[c - FIRST_CHAR];

        float scale = font_size / (float)base_px_height;

        float gw = g->bw * scale;
        float gh = g->bh * scale;

        float x0 = pen_x + g->bl * scale;
        float y0 = pen_y - g->bt * scale;
        float x1 = x0 + gw;
        float y1 = y0 + gh;

        float u0 = g->tx0;
        float v0 = g->ty0;
        float u1 = g->tx1;
        float v1 = g->ty1;

        float vertices[] = {
            x0, y0, u0, v0,
            x1, y0, u1, v0,
            x1, y1, u1, v1,
            x0, y0, u0, v0,
            x1, y1, u1, v1,
            x0, y1, u0, v1
        };

        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);

        GLint pos_loc = glGetAttribLocation(ctx->text_program, "a_pos");
        GLint uv_loc  = glGetAttribLocation(ctx->text_program, "a_uv");

        glEnableVertexAttribArray(pos_loc);
        glEnableVertexAttribArray(uv_loc);

        glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 4*sizeof(float), (void*)0);
        glVertexAttribPointer(uv_loc, 2, GL_FLOAT, GL_FALSE, 4*sizeof(float), (void*)(2*sizeof(float)));

        glActiveTexture(GL_TEXTURE0);

        glBindTexture(GL_TEXTURE_2D, ctx->font_atlas_tex);
        glUniform1i(glGetUniformLocation(ctx->text_program, "u_tex"), 0);

        glDrawArrays(GL_TRIANGLES, 0, 6);

        glDisableVertexAttribArray(pos_loc);
        glDisableVertexAttribArray(uv_loc);

        pen_x += g->ax * scale;
    }
}

