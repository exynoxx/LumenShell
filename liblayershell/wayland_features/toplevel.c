#include "toplevel.h"
#include "registry.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string_ex.h>

// Window tracking structure
typedef struct toplevel_window {
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *app_id;
    char *title;
    struct wl_list link;
} toplevel_window_t;

// Global state
static struct zwlr_foreign_toplevel_manager_v1 *toplevel_manager = NULL;
static struct wl_seat *seat = NULL;
static struct wl_list windows;

static toplevel_window_new callback_new = NULL;
static void* callback_new_data = NULL;
static toplevel_window_rm callback_rm = NULL;
static void* callback_rm_data = NULL;
static toplevel_window_focus callback_focus = NULL;
static void* callback_focus_data = NULL;

// Forward declarations
static void toplevel_handle_title(void *data, 
                                  struct zwlr_foreign_toplevel_handle_v1 *handle,
                                  const char *title);
static void toplevel_handle_app_id(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle,
                                   const char *app_id);
static void toplevel_handle_done(void *data,
                                 struct zwlr_foreign_toplevel_handle_v1 *handle);
static void toplevel_handle_closed(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle);
static void toplevel_handle_state(void *data,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle,
                                  struct wl_array *state);
static void toplevel_handle_output_enter(void *data,
                                         struct zwlr_foreign_toplevel_handle_v1 *handle,
                                         struct wl_output *output);
static void toplevel_handle_output_leave(void *data,
                                         struct zwlr_foreign_toplevel_handle_v1 *handle,
                                         struct wl_output *output);
static void toplevel_handle_parent(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle,
                                   struct zwlr_foreign_toplevel_handle_v1 *parent);

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_handle_listener = {
    .title = toplevel_handle_title,
    .app_id = toplevel_handle_app_id,
    .output_enter = toplevel_handle_output_enter,
    .output_leave = toplevel_handle_output_leave,
    .state = toplevel_handle_state,
    .done = toplevel_handle_done,
    .closed = toplevel_handle_closed,
    .parent = toplevel_handle_parent,
};

// Create new window entry
static toplevel_window_t* window_create(struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = calloc(1, sizeof(toplevel_window_t));
    window->handle = handle;
    window->app_id = NULL;
    window->title = NULL;
    wl_list_insert(&windows, &window->link);
    return window;
}

// Find window by app_id and title
static toplevel_window_t* window_find(const char *app_id, const char *title) {
    toplevel_window_t *window;
    wl_list_for_each(window, &windows, link) {
        if (window->app_id && window->title &&
            strcmp(window->app_id, app_id) == 0 &&
            strcmp(window->title, title) == 0) {
            return window;
        }
    }
    return NULL;
}

// Destroy window entry
static void window_destroy(toplevel_window_t *window) {
    if (callback_rm && window->app_id && window->title) {
        callback_rm(window->app_id, window->title, callback_rm_data);
    }
    
    wl_list_remove(&window->link);
    free(window->app_id);
    free(window->title);
    free(window);
}

// Handle listeners
static void toplevel_handle_title(void *data,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle,
                                  const char *title) {
    toplevel_window_t *window = data;
    free(window->title);
    window->title = strdup(title);
}

static void toplevel_handle_app_id(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle,
                                   const char *app_id) {
    toplevel_window_t *window = data;
    free(window->app_id);
    window->app_id = strdup(app_id);

    if (callback_new && window->app_id && window->title) {
        callback_new(window->app_id, window->title, callback_new_data);
    }
}

static void toplevel_handle_done(void *data,
                                 struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = data;
    if (callback_focus && window->app_id && window->title) {
        callback_focus(window->app_id, window->title, callback_focus_data);
    }
}

static void toplevel_handle_closed(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = data;
    window_destroy(window);
}

static void toplevel_handle_state(void *data,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle,
                                  struct wl_array *state) {
    // Could track window state here if needed
}

static void toplevel_handle_output_enter(void *data,
                                         struct zwlr_foreign_toplevel_handle_v1 *handle,
                                         struct wl_output *output) {
}

static void toplevel_handle_output_leave(void *data,
                                         struct zwlr_foreign_toplevel_handle_v1 *handle,
                                         struct wl_output *output) {
}

static void toplevel_handle_parent(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle,
                                   struct zwlr_foreign_toplevel_handle_v1 *parent) {
}

// Manager listener
static void toplevel_manager_handle_toplevel(void *data,
                                             struct zwlr_foreign_toplevel_manager_v1 *manager,
                                             struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = window_create(handle);
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_handle_listener, window);
}

static void toplevel_manager_handle_finished(void *data,
                                             struct zwlr_foreign_toplevel_manager_v1 *manager) {
    // Compositor is shutting down
}

static const struct zwlr_foreign_toplevel_manager_v1_listener toplevel_manager_listener = {
    .toplevel = toplevel_manager_handle_toplevel,
    .finished = toplevel_manager_handle_finished,
};

// Seat listener (needed for focus)
static void seat_handle_capabilities(void *data, struct wl_seat *wl_seat,
                                     uint32_t capabilities) {
    // We just need the seat reference for activation
}

static void seat_handle_name(void *data, struct wl_seat *wl_seat, const char *name) {
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_handle_capabilities,
    .name = seat_handle_name,
};

// Registry handlers
static void toplevel_registry_handler(void *data, struct wl_registry *registry,
                                      uint32_t name, const char *interface,
                                      uint32_t version) {
    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        toplevel_manager = wl_registry_bind(registry, name,
                                           &zwlr_foreign_toplevel_manager_v1_interface, 3);
        zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_manager,
                                                     &toplevel_manager_listener, NULL);
    } else if (strcmp(interface, wl_seat_interface.name) == 0) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    }
}

// Public API
void toplevel_init(void) {
    wl_list_init(&windows);
    registry_add_handler("zwlr_foreign_toplevel_manager_v1", toplevel_registry_handler, NULL);
    registry_add_handler("wl_seat", toplevel_registry_handler, NULL);
}

void toplevel_cleanup(void) {
    toplevel_window_t *window, *tmp;
    wl_list_for_each_safe(window, tmp, &windows, link) {
        window_destroy(window);
    }
    
    if (seat) {
        wl_seat_destroy(seat);
        seat = NULL;
    }
    
    if (toplevel_manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(toplevel_manager);
        toplevel_manager = NULL;
    }
}

void register_on_window_new(toplevel_window_new cb, void* user_data) {
    callback_new = cb;
    callback_new_data = user_data;
}

void register_on_window_rm(toplevel_window_rm cb, void* user_data) {
    callback_rm = cb;
    callback_rm_data = user_data;
}

void register_on_window_focus(toplevel_window_focus cb, void* user_data) {
    callback_focus = cb;
    callback_focus_data = user_data;
}

void toplevel_focus_window(const char* app_id, const char* title) {
    if (!seat) {
        fprintf(stderr, "No seat available for window activation\n");
        return;
    }
    
    toplevel_window_t *window = window_find(app_id, title);
    if (!window) {
        fprintf(stderr, "Window not found: %s - %s\n", app_id, title);
        return;
    }
    
    // This activates (focuses) the window
    zwlr_foreign_toplevel_handle_v1_activate(window->handle, seat);
    printf("Focused window: %s - %s\n", app_id, title);
}