#ifndef OUTPUT_H
#define OUTPUT_H

#include <stdint.h>

struct wl_output;

typedef struct surface_size_t {
    int width;
    int height;
} surface_size_t;

void output_init(void);
void output_destroy(void);
surface_size_t *get_screen_size(void);
int32_t get_output_scale(void);

// First output with a current mode, else any output, else NULL.
struct wl_output *output_get_primary(void);

// Connector name (wl_output v4) for a bound proxy, or NULL if unknown/unnamed.
const char *output_name_for_proxy(struct wl_output *proxy);

#endif
