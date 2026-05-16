
#include "font.h"
#include <ft2build.h>
#include FT_FREETYPE_H  // this defines FT_Library, FT_Face, etc.

Glyph glyphs[NUM_CHARS];
int base_px_height = 48; // rasterization baseline used to build atlas

bool dk_font_init(dk_context *ctx) {  
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


int dk_width_of(dk_context *ctx, const char *text, float font_size){
    float scale = font_size / (float)base_px_height;
    size_t len = strlen(text);

    int total_w = 0;
    for (size_t i = 0; i < len; ++i){
        unsigned char c = (unsigned char)text[i];
        if (c < FIRST_CHAR || c > LAST_CHAR) continue;
        Glyph *g = &glyphs[c - FIRST_CHAR];
        total_w += g->ax * scale;
    }

    return total_w;
}

int dk_height_of(dk_context *ctx, const char *text, float font_size){
    float scale = font_size / (float)base_px_height;
    size_t len = strlen(text);

    int total_h = 0;
    for (size_t i = 0; i < len; ++i){
        unsigned char c = (unsigned char)text[i];
        if (c < FIRST_CHAR || c > LAST_CHAR) continue;
        Glyph *g = &glyphs[c - FIRST_CHAR];
        total_h += g->ay * scale;
    }

    return total_h;
}