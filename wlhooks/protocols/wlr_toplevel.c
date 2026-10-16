#include "wlr_toplevel.h"
#include "window_list.h"
#include "registry.h"
#include "output.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#include <stdio.h>
#include <string.h>

#define WLR_TOPLEVEL_MAX_VERSION 3

static struct zwlr_foreign_toplevel_manager_v1 *manager = NULL;

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
    toplevel_window_t *w = window_list_create(h);
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
