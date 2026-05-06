#ifndef OUTPUT_H
#define OUTPUT_H

#include <stdint.h>

typedef struct surface_size_t {
    int width;
    int height;
} surface_size_t;

void output_init(void);
void output_destroy();
surface_size_t *get_screen_size();
int32_t get_output_scale();

#endif