#include "ext_toplevel.h"
#include "wlr_toplevel.h"
#include "window_list.h"
#include "registry.h"
#include "../generated/ext-foreign-toplevel-list-v1-client-protocol.h"

#include <stdio.h>
#include <string.h>

static struct ext_foreign_toplevel_list_v1 *manager = NULL;

static void op_destroy_handle(toplevel_window_t *w) {
    if (w->handle) {
        ext_foreign_toplevel_handle_v1_destroy(w->handle);
        w->handle = NULL;
    }
}

// ext-foreign-toplevel-list is enumeration-only; activate/minimize/close
// remain NULL and are reported as unsupported by the public API.
static const toplevel_window_ops_t ext_ops = {
    .destroy_handle = op_destroy_handle,
};

static void on_title     (void *data, struct ext_foreign_toplevel_handle_v1 *h, const char *title)  { window_list_set_title (data, title);  }
static void on_app_id    (void *data, struct ext_foreign_toplevel_handle_v1 *h, const char *app_id) { window_list_set_app_id(data, app_id); }
static void on_identifier(void *data, struct ext_foreign_toplevel_handle_v1 *h, const char *identifier) {}
static void on_done      (void *data, struct ext_foreign_toplevel_handle_v1 *h)                     { window_list_emit_done(data);          }

static void on_closed(void *data, struct ext_foreign_toplevel_handle_v1 *h) {
    toplevel_window_t *w = data;
    ext_foreign_toplevel_handle_v1_destroy(h);
    w->handle = NULL;
    window_list_destroy(w);
}

static const struct ext_foreign_toplevel_handle_v1_listener handle_listener = {
    .closed     = on_closed,
    .done       = on_done,
    .title      = on_title,
    .app_id     = on_app_id,
    .identifier = on_identifier,
};

static void on_toplevel(void *data,
                        struct ext_foreign_toplevel_list_v1 *list,
                        struct ext_foreign_toplevel_handle_v1 *h) {
    // wlr is authoritative when both protocols are advertised.
    if (wlr_toplevel_available()) {
        ext_foreign_toplevel_handle_v1_destroy(h);
        return;
    }
    toplevel_window_t *w = window_list_create(h, &ext_ops);
    ext_foreign_toplevel_handle_v1_add_listener(h, &handle_listener, w);
}

static void on_finished(void *data, struct ext_foreign_toplevel_list_v1 *list) {}

static const struct ext_foreign_toplevel_list_v1_listener list_listener = {
    .toplevel = on_toplevel,
    .finished = on_finished,
};

static void registry_handler(void *data, struct wl_registry *registry,
                             uint32_t name, const char *interface, uint32_t version) {
    manager = wl_registry_bind(registry, name, &ext_foreign_toplevel_list_v1_interface, 1);
    ext_foreign_toplevel_list_v1_add_listener(manager, &list_listener, NULL);
}

void ext_toplevel_init(void) {
    registry_add_handler(ext_foreign_toplevel_list_v1_interface.name,
                         registry_handler, NULL);
}

void ext_toplevel_cleanup(void) {
    if (manager) {
        ext_foreign_toplevel_list_v1_destroy(manager);
        manager = NULL;
    }
}
