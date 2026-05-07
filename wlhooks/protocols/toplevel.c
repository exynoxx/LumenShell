#include "toplevel.h"
#include "registry.h"
#include "seat.h"
#include "../generated/ext-foreign-toplevel-list-v1-client-protocol.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// Window tracking: backend-agnostic record. Exactly one of (wlr_handle, ext_handle)
// is non-NULL depending on which protocol the compositor exposes.
typedef struct toplevel_window {
    struct zwlr_foreign_toplevel_handle_v1 *wlr_handle;
    struct ext_foreign_toplevel_handle_v1  *ext_handle;
    uint32_t id;
    char *app_id;
    char *title;
    bool activated;
    bool announced;
    struct wl_list link;
} toplevel_window_t;

// Manager bindings — wlr is preferred when both are advertised, since it
// supports activate / minimize / close. ext is enumeration-only.
static struct zwlr_foreign_toplevel_manager_v1 *wlr_manager = NULL;
static struct ext_foreign_toplevel_list_v1     *ext_manager = NULL;

#define WLR_TOPLEVEL_MAX_VERSION 3

static struct wl_list windows;
// Start at 1 so 0 stays available as a "no window" sentinel for callers.
static uint32_t global_window_id = 1;

static toplevel_window_new   callback_new   = NULL;
static void                 *callback_new_data   = NULL;
static toplevel_window_rm    callback_rm    = NULL;
static void                 *callback_rm_data    = NULL;
static toplevel_window_focus callback_focus = NULL;
static void                 *callback_focus_data = NULL;

static toplevel_window_t* window_create(void) {
    toplevel_window_t *window = calloc(1, sizeof(toplevel_window_t));
    window->id = global_window_id++;
    wl_list_insert(&windows, &window->link);
    return window;
}

static void emit_window_new_if_ready(toplevel_window_t *window) {
    if (!window || window->announced) return;
    if (!window->app_id || !window->title) return;
    if (!callback_new) return;

    window->announced = true;
    callback_new(window->id, window->app_id, window->title, callback_new_data);
}

static void window_destroy(toplevel_window_t *window) {
    if (callback_rm && window->announced) {
        callback_rm(window->id, callback_rm_data);
    }

    wl_list_remove(&window->link);
    free(window->app_id);
    free(window->title);
    free(window);
}

static toplevel_window_t* window_find(uint32_t id) {
    toplevel_window_t *window;
    wl_list_for_each(window, &windows, link) {
        if (window->id == id) return window;
    }
    return NULL;
}

// ─────────────────────────── wlr-foreign-toplevel ────────────────────────────

static void wlr_handle_title(void *data,
                             struct zwlr_foreign_toplevel_handle_v1 *handle,
                             const char *title) {
    toplevel_window_t *window = data;
    free(window->title);
    window->title = strdup(title);
    emit_window_new_if_ready(window);
}

static void wlr_handle_app_id(void *data,
                              struct zwlr_foreign_toplevel_handle_v1 *handle,
                              const char *app_id) {
    toplevel_window_t *window = data;
    free(window->app_id);
    window->app_id = strdup(app_id);
    emit_window_new_if_ready(window);
}

static void wlr_handle_done(void *data,
                            struct zwlr_foreign_toplevel_handle_v1 *handle) {
    emit_window_new_if_ready((toplevel_window_t *)data);
}

static void wlr_handle_closed(void *data,
                              struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = data;
    zwlr_foreign_toplevel_handle_v1_destroy(handle);
    window->wlr_handle = NULL;
    window_destroy(window);
}

static void wlr_handle_state(void *data,
                             struct zwlr_foreign_toplevel_handle_v1 *handle,
                             struct wl_array *state) {
    toplevel_window_t *window = data;
    bool is_activated = false;

    uint32_t *state_ptr;
    wl_array_for_each(state_ptr, state) {
        if (*state_ptr == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED) {
            is_activated = true;
            break;
        }
    }

    if (is_activated && !window->activated) {
        window->activated = true;
        if (callback_focus && window->announced) {
            callback_focus(window->id, callback_focus_data);
        }
    } else if (!is_activated && window->activated) {
        window->activated = false;
    }
}

static void wlr_handle_output_enter(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) {}
static void wlr_handle_output_leave(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) {}
static void wlr_handle_parent     (void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct zwlr_foreign_toplevel_handle_v1 *p) {}

static const struct zwlr_foreign_toplevel_handle_v1_listener wlr_handle_listener = {
    .title        = wlr_handle_title,
    .app_id       = wlr_handle_app_id,
    .output_enter = wlr_handle_output_enter,
    .output_leave = wlr_handle_output_leave,
    .state        = wlr_handle_state,
    .done         = wlr_handle_done,
    .closed       = wlr_handle_closed,
    .parent       = wlr_handle_parent,
};

static void wlr_manager_toplevel(void *data,
                                 struct zwlr_foreign_toplevel_manager_v1 *manager,
                                 struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = window_create();
    window->wlr_handle = handle;
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &wlr_handle_listener, window);
}

static void wlr_manager_finished(void *data,
                                 struct zwlr_foreign_toplevel_manager_v1 *manager) {}

static const struct zwlr_foreign_toplevel_manager_v1_listener wlr_manager_listener = {
    .toplevel = wlr_manager_toplevel,
    .finished = wlr_manager_finished,
};

static void wlr_registry_handler(void *data, struct wl_registry *registry,
                                 uint32_t name, const char *interface,
                                 uint32_t version) {
    uint32_t v = version > WLR_TOPLEVEL_MAX_VERSION ? WLR_TOPLEVEL_MAX_VERSION : version;
    wlr_manager = wl_registry_bind(registry, name,
                                   &zwlr_foreign_toplevel_manager_v1_interface, v);
    zwlr_foreign_toplevel_manager_v1_add_listener(wlr_manager,
                                                  &wlr_manager_listener, NULL);
}

// ───────────────────────── ext-foreign-toplevel-list ─────────────────────────

static void ext_handle_title(void *data,
                             struct ext_foreign_toplevel_handle_v1 *handle,
                             const char *title) {
    toplevel_window_t *window = data;
    free(window->title);
    window->title = strdup(title);
}

static void ext_handle_app_id(void *data,
                              struct ext_foreign_toplevel_handle_v1 *handle,
                              const char *app_id) {
    toplevel_window_t *window = data;
    free(window->app_id);
    window->app_id = strdup(app_id);
}

static void ext_handle_identifier(void *data,
                                  struct ext_foreign_toplevel_handle_v1 *handle,
                                  const char *identifier) {}

static void ext_handle_done(void *data,
                            struct ext_foreign_toplevel_handle_v1 *handle) {
    emit_window_new_if_ready((toplevel_window_t *)data);
}

static void ext_handle_closed(void *data,
                              struct ext_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = data;
    ext_foreign_toplevel_handle_v1_destroy(handle);
    window->ext_handle = NULL;
    window_destroy(window);
}

static const struct ext_foreign_toplevel_handle_v1_listener ext_handle_listener = {
    .closed     = ext_handle_closed,
    .done       = ext_handle_done,
    .title      = ext_handle_title,
    .app_id     = ext_handle_app_id,
    .identifier = ext_handle_identifier,
};

static void ext_list_toplevel(void *data,
                              struct ext_foreign_toplevel_list_v1 *list,
                              struct ext_foreign_toplevel_handle_v1 *handle) {
    // wlr is authoritative when both are present — ignore ext events.
    if (wlr_manager) {
        ext_foreign_toplevel_handle_v1_destroy(handle);
        return;
    }
    toplevel_window_t *window = window_create();
    window->ext_handle = handle;
    ext_foreign_toplevel_handle_v1_add_listener(handle, &ext_handle_listener, window);
}

static void ext_list_finished(void *data,
                              struct ext_foreign_toplevel_list_v1 *list) {}

static const struct ext_foreign_toplevel_list_v1_listener ext_list_listener = {
    .toplevel = ext_list_toplevel,
    .finished = ext_list_finished,
};

static void ext_registry_handler(void *data, struct wl_registry *registry,
                                 uint32_t name, const char *interface,
                                 uint32_t version) {
    ext_manager = wl_registry_bind(registry, name,
                                   &ext_foreign_toplevel_list_v1_interface, 1);
    ext_foreign_toplevel_list_v1_add_listener(ext_manager, &ext_list_listener, NULL);
}

// ─────────────────────────────── Public API ──────────────────────────────────

void toplevel_init(void) {
    wl_list_init(&windows);
    registry_add_handler("zwlr_foreign_toplevel_manager_v1", wlr_registry_handler, NULL);
    registry_add_handler(ext_foreign_toplevel_list_v1_interface.name,
                         ext_registry_handler, NULL);
}

void toplevel_cleanup(void) {
    toplevel_window_t *window, *tmp;
    wl_list_for_each_safe(window, tmp, &windows, link) {
        if (window->wlr_handle) zwlr_foreign_toplevel_handle_v1_destroy(window->wlr_handle);
        if (window->ext_handle) ext_foreign_toplevel_handle_v1_destroy(window->ext_handle);
        window->wlr_handle = NULL;
        window->ext_handle = NULL;
        window_destroy(window);
    }

    if (wlr_manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(wlr_manager);
        wlr_manager = NULL;
    }
    if (ext_manager) {
        ext_foreign_toplevel_list_v1_destroy(ext_manager);
        ext_manager = NULL;
    }
}

void register_on_window_new(toplevel_window_new cb, void* user_data) {
    callback_new = cb;
    callback_new_data = user_data;

    toplevel_window_t *window;
    wl_list_for_each(window, &windows, link) {
        emit_window_new_if_ready(window);
    }
}

void register_on_window_rm(toplevel_window_rm cb, void* user_data) {
    callback_rm = cb;
    callback_rm_data = user_data;
}

void register_on_window_focus(toplevel_window_focus cb, void* user_data) {
    callback_focus = cb;
    callback_focus_data = user_data;
    if (!callback_focus) return;

    toplevel_window_t *window;
    wl_list_for_each(window, &windows, link) {
        if (window->activated && window->announced) {
            callback_focus(window->id, callback_focus_data);
        }
    }
}

void toplevel_activate_by_id(uint32_t id) {
    toplevel_window_t *window = window_find(id);
    if (!window) {
        fprintf(stderr, "Window not found: %u\n", id);
        return;
    }

    if (window->wlr_handle) {
        struct wl_seat *seat = get_wl_seat();
        if (!seat) {
            fprintf(stderr, "toplevel_activate: no seat\n");
            return;
        }
        zwlr_foreign_toplevel_handle_v1_activate(window->wlr_handle, seat);
        return;
    }

    fprintf(stderr, "toplevel_activate: foreign-toplevel control not supported by compositor\n");
}

void toplevel_minimize_by_id(uint32_t id) {
    toplevel_window_t *window = window_find(id);
    if (!window) {
        fprintf(stderr, "Window not found: %u\n", id);
        return;
    }

    if (window->wlr_handle) {
        zwlr_foreign_toplevel_handle_v1_set_minimized(window->wlr_handle);
        return;
    }

    fprintf(stderr, "toplevel_minimize: not supported by compositor\n");
}

void toplevel_close_by_id(uint32_t id) {
    toplevel_window_t *window = window_find(id);
    if (!window) {
        fprintf(stderr, "Window not found: %u\n", id);
        return;
    }

    if (window->wlr_handle) {
        zwlr_foreign_toplevel_handle_v1_close(window->wlr_handle);
        return;
    }

    fprintf(stderr, "toplevel_close: not supported by compositor\n");
}
