#include "toplevel.h"
#include "registry.h"
#include "seat.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// Window tracking structure
typedef struct toplevel_window {
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    uint32_t id;
    char *app_id;
    char *title;
    bool activated;
    struct wl_list link;
} toplevel_window_t;

// Global state
static struct zwlr_foreign_toplevel_manager_v1 *toplevel_manager = NULL;
static struct wl_list windows;
static uint32_t global_window_id;

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
    window->id = global_window_id++;
    window->handle = handle;
    window->app_id = NULL;
    window->title = NULL;
    wl_list_insert(&windows, &window->link);
    return window;
}

// Destroy window entry
static void window_destroy(toplevel_window_t *window) {
    if (callback_rm && window->app_id && window->title) {
        callback_rm(window->id, callback_rm_data);
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
        callback_new(window->id, window->app_id, window->title, callback_new_data);
    }
}

static void toplevel_handle_done(void *data,
                                 struct zwlr_foreign_toplevel_handle_v1 *handle) {
}

static void toplevel_handle_closed(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = data;
    window_destroy(window);
}

static void toplevel_handle_state(void *data,
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
    
    // Detect focus change
    if (is_activated && !window->activated) {
        window->activated = true;
        if (callback_focus && window->app_id && window->title) {
            callback_focus(window->id, callback_focus_data);
        }
    } else if (!is_activated && window->activated) {
        window->activated = false;
        //TODO unfocus cb if exists
    }
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

// Registry handlers
static void toplevel_registry_handler(void *data, struct wl_registry *registry,
                                      uint32_t name, const char *interface,
                                      uint32_t version) {
    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        toplevel_manager = wl_registry_bind(registry, name,
                                           &zwlr_foreign_toplevel_manager_v1_interface, 3);
        zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_manager,
                                                     &toplevel_manager_listener, NULL);
    }
}

// Public API
void toplevel_init(void) {
    wl_list_init(&windows);
    registry_add_handler("zwlr_foreign_toplevel_manager_v1", toplevel_registry_handler, NULL);
}

void toplevel_cleanup(void) {
    toplevel_window_t *window, *tmp;
    wl_list_for_each_safe(window, tmp, &windows, link) {
        window_destroy(window);
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

static toplevel_window_t* window_find(uint32_t id) {
    printf("window_find");
    toplevel_window_t *window;
    wl_list_for_each(window, &windows, link) {
        if (window->id == id) {
            return window;
        }
    }
    return NULL;
}


void toplevel_activate(toplevel_window_t *window, struct wl_seat *seat) {
    if (!seat) {
        fprintf(stderr, "No seat available in toplevel_activate\n");
        return;
    }

    if (!window->handle) {
        fprintf(stderr, "toplevel_activate: no window handle\n");
        return;
    }

    //printf("zwlr_foreign_toplevel_handle_v1_activate %s\n", window->title);
    zwlr_foreign_toplevel_handle_v1_activate(window->handle, seat);
}

void toplevel_activate_by_id(uint32_t id) {
    //printf("enter toplevel_activate_by_id");
    toplevel_window_t *window = window_find(id);
    if (!window) {
        fprintf(stderr, "Window not found: %u\n", id);
        return;
    }
    
    struct wl_seat *seat = get_wl_seat();
    toplevel_activate(window, seat);
}

void toplevel_minimize(toplevel_window_t *window){
    if (!window->handle) {
        fprintf(stderr, "toplevel_activate: no window handle\n");
        return;
    }

    //printf("zwlr_foreign_toplevel_handle_v1_set_minimized %s\n", window->title);
    zwlr_foreign_toplevel_handle_v1_set_minimized(window->handle);
}

void toplevel_minimize_by_id(uint32_t id){
    //printf("enter toplevel_minimize_by_id");
    toplevel_window_t *window = window_find(id);
    if (!window) {
        fprintf(stderr, "Window not found: %u\n", id);
        return;
    }

    toplevel_minimize(window);
}