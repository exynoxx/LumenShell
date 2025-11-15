#ifndef DRAWKIT_NANOSVG_H
#define DRAWKIT_NANOSVG_H

#include "texture.h"

Image *rasterize_svg_to_rgba(const char* filename, int target_width, int target_height);

#endif