#include <wayland-client.h>
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

struct toplevel {
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *title;
    char *app_id;
    struct wl_list link;
};

static void toplevel_handle_title(void *data,
        struct zwlr_foreign_toplevel_handle_v1 *handle,
        const char *title) {
    struct toplevel *toplevel = data;
    free(toplevel->title);
    toplevel->title = strdup(title);
}

static void toplevel_handle_app_id(void *data,
        struct zwlr_foreign_toplevel_handle_v1 *handle,
        const char *app_id) {
    struct toplevel *toplevel = data;
    free(toplevel->app_id);
    toplevel->app_id = strdup(app_id);
    
    // Use app_id to find icon
    printf("New app: %s\n", app_id);
}

static void toplevel_handle_closed(void *data,
        struct zwlr_foreign_toplevel_handle_v1 *handle) {
    struct toplevel *toplevel = data;
    wl_list_remove(&toplevel->link);
    free(toplevel->title);
    free(toplevel->app_id);
    free(toplevel);
}

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_listener = {
    .title = toplevel_handle_title,
    .app_id = toplevel_handle_app_id,
    .state = /* ... */,
    .done = /* ... */,
    .closed = toplevel_handle_closed,
    /* other callbacks */
};

static void toplevel_manager_handle_toplevel(void *data,
        struct zwlr_foreign_toplevel_manager_v1 *manager,
        struct zwlr_foreign_toplevel_handle_v1 *handle) {
    struct toplevel *toplevel = calloc(1, sizeof(*toplevel));
    toplevel->handle = handle;
    
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_listener, toplevel);
    
    // Add to your list
    wl_list_insert(&toplevels, &toplevel->link);
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = toplevel_manager_handle_toplevel,
    .finished = /* ... */,
};