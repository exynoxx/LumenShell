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

// Returns the proxy of the first output with a current mode, or any output if
// none have reported one yet. Used by screencopy etc. NULL if no outputs.
struct wl_output *output_get_primary(void);

// Connector name (e.g. "HDMI-A-1", wl_output v4) for a bound output proxy, or
// NULL if the proxy isn't one of ours / has no name yet. Used to map a
// foreign-toplevel output_enter back to a Gdk.Monitor connector.
const char *output_name_for_proxy(struct wl_output *proxy);

#endif
