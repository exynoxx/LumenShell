#include <stdio.h>
#include <stdlib.h>
#define NANOSVG_IMPLEMENTATION
#include <nanosvg/nanosvg.h>
#define NANOSVGRAST_IMPLEMENTATION
#include <nanosvg/nanosvgrast.h>  // rasterizer
#include "nanosvg.h"

Image *rasterize_svg_to_rgba(const char* filename, int target_width, int target_height) {
    // Parse the SVG file
    NSVGimage* image = nsvgParseFromFile(filename, "px", 96.0f);
    if (!image) {
        fprintf(stderr, "Failed to parse SVG file: %s\n", filename);
        return NULL;
    }

    // Allocate pixel buffer
    uint8_t* rgba = (uint8_t*)malloc(target_width * target_height * 4);
    if (!rgba) {
        nsvgDelete(image);
        return NULL;
    }

    // Create rasterizer
    NSVGrasterizer* rast = nsvgCreateRasterizer();
    if (!rast) {
        fprintf(stderr, "Failed to create rasterizer\n");
        free(rgba);
        nsvgDelete(image);
        return NULL;
    }

    // Rasterize SVG into buffer
    nsvgRasterize(rast, image, 0, 0, 
                  (float)target_width / image->width,
                  rgba, target_width, target_height, target_width * 4);

    // Cleanup
    nsvgDeleteRasterizer(rast);
    nsvgDelete(image);

    Image *ret = (Image *)malloc(sizeof(Image));
    ret->width = target_width;
    ret->height = target_height;
    ret->channels = 4;
    ret->data = rgba;

    return ret;
}
