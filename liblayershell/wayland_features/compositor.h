#ifndef COMPOSITOR_H
#define COMPOSITOR_H

void compositor_init();
void compositor_cleanup();

struct wl_compositor *get_compositor();

#endif