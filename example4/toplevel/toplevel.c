#include "toplevel.h"
#include "registry.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string_ex.h>
#include <stdbool.h>

// Window tracking structure
typedef struct toplevel_window {
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *app_id;
    char *title;
    bool activated;
    struct wl_list link;
} toplevel_window_t;

// Global state
static struct zwlr_foreign_toplevel_manager_v1 *toplevel_manager = NULL;
static struct wl_list windows;

// Forward declarations
extern void toplevel_created(toplevel_window_t *window);
extern void toplevel_destroyed(toplevel_window_t *window);

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


// Destroy window entry
static void window_destroy(toplevel_window_t *window) {
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
}

static void toplevel_handle_done(void *data,
                                 struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = data;
    toplevel_created(window);
}

static void toplevel_handle_closed(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle) {
    toplevel_window_t *window = data;
    toplevel_destroyed(window);
    window_destroy(window);
}

static void toplevel_handle_state(void *data,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle,
                                  struct wl_array *state) {
    printf("toplevel_handle_state");

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
    } else if (!is_activated && window->activated) {
        window->activated = false;
        //TODO call callback
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
/* 
void toplevel_focus_window(const char* app_id, const char* title) {
    printf("toplevel_focus_window");
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
    printf("Focusing window: %s - %s\n", app_id, title);
    zwlr_foreign_toplevel_handle_v1_activate(window->handle, seat);
} */