#include "toplevel.h"
#include "window_list.h"
#include "wlr_toplevel.h"
#include "seat.h"

#include <stdio.h>

void toplevel_init(void) {
    window_list_init();
    wlr_toplevel_init();
}

void toplevel_cleanup(void) {
    wlr_toplevel_cleanup();
    window_list_cleanup();
}

void register_on_window_new  (toplevel_window_new   cb, void *user_data) { window_list_register_new  (cb, user_data); }
void register_on_window_rm   (toplevel_window_rm    cb, void *user_data) { window_list_register_rm   (cb, user_data); }
void register_on_window_focus(toplevel_window_focus cb, void *user_data) { window_list_register_focus(cb, user_data); }
void register_on_window_output_changed(toplevel_window_output cb, void *user_data) { window_list_register_output(cb, user_data); }

static toplevel_window_t *find_or_warn(uint32_t id) {
    toplevel_window_t *w = window_list_find(id);
    if (!w) fprintf(stderr, "toplevel: window %u not found\n", id);
    return w;
}

void toplevel_activate_by_id(uint32_t id) {
    toplevel_window_t *w = find_or_warn(id);
    if (!w) return;
    struct wl_seat *s = get_wl_seat();
    if (!s) { fprintf(stderr, "toplevel: no seat for activate\n"); return; }
    zwlr_foreign_toplevel_handle_v1_activate(w->handle, s);
}

void toplevel_minimize_by_id(uint32_t id) {
    toplevel_window_t *w = find_or_warn(id);
    if (w) zwlr_foreign_toplevel_handle_v1_set_minimized(w->handle);
}

void toplevel_close_by_id(uint32_t id) {
    toplevel_window_t *w = find_or_warn(id);
    if (w) zwlr_foreign_toplevel_handle_v1_close(w->handle);
}

// Silent on a missing id: the panel re-pushes rectangles on every re-layout,
// so a window that closed a frame earlier must vanish quietly.
void toplevel_set_rectangle_by_id(uint32_t id, struct wl_surface *surface,
                                  int32_t x, int32_t y, int32_t width, int32_t height) {
    toplevel_window_t *w = window_list_find(id);
    if (w) zwlr_foreign_toplevel_handle_v1_set_rectangle(w->handle, surface, x, y, width, height);
}
