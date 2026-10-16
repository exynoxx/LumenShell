#ifndef OUTPUT_H
#define OUTPUT_H

struct wl_output;

void output_init(void);

// Connector name (wl_output v4) for a bound proxy, or NULL if unknown/unnamed.
const char *output_name_for_proxy(struct wl_output *proxy);

#endif
