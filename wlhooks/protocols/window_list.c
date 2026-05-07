#include "window_list.h"

#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

static struct wl_list windows;
// Start at 1 so 0 stays a valid "no window" sentinel for callers.
static uint32_t next_window_id = 1;

static toplevel_window_new   cb_new;   static void *cb_new_data   = NULL;
static toplevel_window_rm    cb_rm;    static void *cb_rm_data    = NULL;
static toplevel_window_focus cb_focus; static void *cb_focus_data = NULL;

static void emit_new_if_ready(toplevel_window_t *w) {
    if (!w || w->announced) return;
    if (!w->app_id || !w->title) return;
    if (!cb_new) return;
    w->announced = true;
    cb_new(w->id, w->app_id, w->title, cb_new_data);
}

void window_list_init(void) {
    wl_list_init(&windows);
}

void window_list_cleanup(void) {
    toplevel_window_t *w, *tmp;
    wl_list_for_each_safe(w, tmp, &windows, link) {
        if (w->ops && w->ops->destroy_handle) w->ops->destroy_handle(w);
        wl_list_remove(&w->link);
        free(w->app_id);
        free(w->title);
        free(w);
    }
}

toplevel_window_t *window_list_create(void *handle, const toplevel_window_ops_t *ops) {
    toplevel_window_t *w = calloc(1, sizeof(*w));
    w->id     = next_window_id++;
    w->handle = handle;
    w->ops    = ops;
    wl_list_insert(&windows, &w->link);
    return w;
}

toplevel_window_t *window_list_find(uint32_t id) {
    toplevel_window_t *w;
    wl_list_for_each(w, &windows, link) {
        if (w->id == id) return w;
    }
    return NULL;
}

void window_list_set_title(toplevel_window_t *w, const char *title) {
    free(w->title);
    w->title = strdup(title);
    emit_new_if_ready(w);
}

void window_list_set_app_id(toplevel_window_t *w, const char *app_id) {
    free(w->app_id);
    w->app_id = strdup(app_id);
    emit_new_if_ready(w);
}

void window_list_emit_done(toplevel_window_t *w) {
    emit_new_if_ready(w);
}

void window_list_set_activated(toplevel_window_t *w, bool activated) {
    if (activated == w->activated) return;
    w->activated = activated;
    if (activated && cb_focus && w->announced) {
        cb_focus(w->id, cb_focus_data);
    }
}

void window_list_destroy(toplevel_window_t *w) {
    if (cb_rm && w->announced) {
        cb_rm(w->id, cb_rm_data);
    }
    wl_list_remove(&w->link);
    free(w->app_id);
    free(w->title);
    free(w);
}

void window_list_register_new(toplevel_window_new cb, void *user_data) {
    cb_new = cb;
    cb_new_data = user_data;

    // Replay already-announced windows for late subscribers.
    toplevel_window_t *w;
    wl_list_for_each(w, &windows, link) {
        if (!w->announced) emit_new_if_ready(w);
    }
}

void window_list_register_rm(toplevel_window_rm cb, void *user_data) {
    cb_rm = cb;
    cb_rm_data = user_data;
}

void window_list_register_focus(toplevel_window_focus cb, void *user_data) {
    cb_focus = cb;
    cb_focus_data = user_data;
    if (!cb_focus) return;

    toplevel_window_t *w;
    wl_list_for_each(w, &windows, link) {
        if (w->activated && w->announced) cb_focus(w->id, cb_focus_data);
    }
}
