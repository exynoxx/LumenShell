#ifndef FONT_H
#define FONT_H

#include "structures.h"

typedef struct {
    float ax, ay; // advance.x, advance.y (pixels)
    int bw, bh;   // bitmap width, height (pixels)
    int bl, bt;   // bitmap left, bitmap top (bearing)
    float tx0, ty0, tx1, ty1; // texture coords in atlas
} Glyph;

#define FIRST_CHAR 32
#define LAST_CHAR 126
#define NUM_CHARS (LAST_CHAR - FIRST_CHAR + 1)

bool dk_font_init(dk_context *ctx);

int dk_width_of(dk_context *ctx, const char *text, float font_size);
int dk_height_of(dk_context *ctx, const char *text, float font_size);

#endif