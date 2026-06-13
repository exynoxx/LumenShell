#include "wlr_toplevel.h"
#include "window_list.h"
#include "registry.h"
#include "seat.h"
#include "output.h"
#include "../generated/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#include <stdio.h>
#include <string.h>

#define WLR_TOPLEVEL_MAX_VERSION 3

static struct zwlr_foreign_toplevel_manager_v1 *manager = NULL;

static void op_activate(toplevel_window_t *w) {
    struct wl_seat *s = get_wl_seat();
    if (!s) {
        fprintf(stderr, "wlr_toplevel: no seat for activate\n");
        return;
    }
    zwlr_foreign_toplevel_handle_v1_activate(w->handle, s);
}

static void op_minimize(toplevel_window_t *w) {
    zwlr_foreign_toplevel_handle_v1_set_minimized(w->handle);
}

static void op_close(toplevel_window_t *w) {
    zwlr_foreign_toplevel_handle_v1_close(w->handle);
}

static void op_set_rectangle(toplevel_window_t *w, struct wl_surface *surface,
                             int32_t x, int32_t y, int32_t width, int32_t height) {
    zwlr_foreign_toplevel_handle_v1_set_rectangle(w->handle, surface, x, y, width, height);
}

static void op_destroy_handle(toplevel_window_t *w) {
    if (w->handle) {
        zwlr_foreign_toplevel_handle_v1_destroy(w->handle);
        w->handle = NULL;
    }
}

static const toplevel_window_ops_t wlr_ops = {
    .activate       = op_activate,
    .minimize       = op_minimize,
    .close          = op_close,
    .set_rectangle  = op_set_rectangle,
    .destroy_handle = op_destroy_handle,
};

static void on_title (void *data, struct zwlr_foreign_toplevel_handle_v1 *h, const char *title)  { window_list_set_title (data, title);  }
static void on_app_id(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, const char *app_id) { window_list_set_app_id(data, app_id); }
static void on_done  (void *data, struct zwlr_foreign_toplevel_handle_v1 *h)                     { window_list_emit_done(data);          }

static void on_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *h) {
    toplevel_window_t *w = data;
    zwlr_foreign_toplevel_handle_v1_destroy(h);
    w->handle = NULL;
    window_list_destroy(w);
}

static void on_state(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_array *state) {
    bool activated = false;
    uint32_t *p;
    wl_array_for_each(p, state) {
        if (*p == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED) { activated = true; break; }
    }
    window_list_set_activated(data, activated);
}

static void on_output_enter(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) {
    const char *name = output_name_for_proxy(o);
    if (name) window_list_set_output(data, name, true);
}
static void on_output_leave(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) {
    const char *name = output_name_for_proxy(o);
    if (name) window_list_set_output(data, name, false);
}
static void on_parent      (void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct zwlr_foreign_toplevel_handle_v1 *p) {}

static const struct zwlr_foreign_toplevel_handle_v1_listener handle_listener = {
    .title        = on_title,
    .app_id       = on_app_id,
    .output_enter = on_output_enter,
    .output_leave = on_output_leave,
    .state        = on_state,
    .done         = on_done,
    .closed       = on_closed,
    .parent       = on_parent,
};

static void on_toplevel(void *data,
                        struct zwlr_foreign_toplevel_manager_v1 *m,
                        struct zwlr_foreign_toplevel_handle_v1 *h) {
    toplevel_window_t *w = window_list_create(h, &wlr_ops);
    zwlr_foreign_toplevel_handle_v1_add_listener(h, &handle_listener, w);
}

static void on_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *m) {}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = on_toplevel,
    .finished = on_finished,
};

static void registry_handler(void *data, struct wl_registry *registry,
                             uint32_t name, const char *interface, uint32_t version) {
    uint32_t v = version > WLR_TOPLEVEL_MAX_VERSION ? WLR_TOPLEVEL_MAX_VERSION : version;
    manager = wl_registry_bind(registry, name, &zwlr_foreign_toplevel_manager_v1_interface, v);
    zwlr_foreign_toplevel_manager_v1_add_listener(manager, &manager_listener, NULL);
}

void wlr_toplevel_init(void) {
    registry_add_handler("zwlr_foreign_toplevel_manager_v1", registry_handler, NULL);
}

void wlr_toplevel_cleanup(void) {
    if (manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(manager);
        manager = NULL;
    }
}

bool wlr_toplevel_available(void) {
    return manager != NULL;
}
