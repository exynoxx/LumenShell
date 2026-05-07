#ifndef COMPOSITOR_H
#define COMPOSITOR_H

void compositor_init(void);
void compositor_cleanup(void);

struct wl_compositor *get_compositor(void);

#endif