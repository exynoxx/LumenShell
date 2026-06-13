#include "toplevel.h"
#include "window_list.h"
#include "wlr_toplevel.h"
#include "ext_toplevel.h"

#include <stddef.h>
#include <stdio.h>

void toplevel_init(void) {
    window_list_init();
    wlr_toplevel_init();
    ext_toplevel_init();
}

void toplevel_cleanup(void) {
    wlr_toplevel_cleanup();
    ext_toplevel_cleanup();
    window_list_cleanup();
}

void register_on_window_new  (toplevel_window_new   cb, void *user_data) { window_list_register_new  (cb, user_data); }
void register_on_window_rm   (toplevel_window_rm    cb, void *user_data) { window_list_register_rm   (cb, user_data); }
void register_on_window_focus(toplevel_window_focus cb, void *user_data) { window_list_register_focus(cb, user_data); }
void register_on_window_output_changed(toplevel_window_output cb, void *user_data) { window_list_register_output(cb, user_data); }

typedef void (*window_op_fn)(toplevel_window_t *);

static window_op_fn pick_op(const toplevel_window_t *w, size_t offset) {
    if (!w->ops) return NULL;
    return *(window_op_fn *)((const char *)w->ops + offset);
}

#define DISPATCH(id, field, name)                                              \
    do {                                                                       \
        toplevel_window_t *w = window_list_find(id);                           \
        if (!w) { fprintf(stderr, "toplevel: window %u not found\n", id); return; } \
        window_op_fn op = pick_op(w, offsetof(toplevel_window_ops_t, field));  \
        if (!op) { fprintf(stderr, "toplevel: " name " not supported by compositor\n"); return; } \
        op(w);                                                                 \
    } while (0)

void toplevel_activate_by_id(uint32_t id) { DISPATCH(id, activate, "activate"); }
void toplevel_minimize_by_id(uint32_t id) { DISPATCH(id, minimize, "minimize"); }
void toplevel_close_by_id   (uint32_t id) { DISPATCH(id, close,    "close");    }

// Not routed through DISPATCH (that macro only passes the window, and we want
// silence rather than a warning here): the panel re-pushes rectangles on every
// re-layout, so a window that closed a frame earlier must vanish quietly.
void toplevel_set_rectangle_by_id(uint32_t id, struct wl_surface *surface,
                                  int32_t x, int32_t y, int32_t width, int32_t height) {
    toplevel_window_t *w = window_list_find(id);
    if (!w || !w->ops || !w->ops->set_rectangle) return;
    w->ops->set_rectangle(w, surface, x, y, width, height);
}
