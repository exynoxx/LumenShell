#include "toplevel.h"
#include "registry.h"
#include <stdio.h>
#include <string.h>

static struct zwlr_foreign_toplevel_manager_v1 *toplevel_manager = NULL;
static struct toplevel_info *toplevels = NULL;

/* static char *find_icon_for_app_id(const char *app_id) {
    if (!app_id) return NULL;
    
    const char *desktop_paths[] = {
        "/usr/share/applications/",
        "/usr/local/share/applications/",
        NULL
    };
    
    char desktop_file[512];
    char line[512];
    char *icon_name = NULL;
    
    // Try to find .desktop file
    for (int i = 0; desktop_paths[i]; i++) {
        snprintf(desktop_file, sizeof(desktop_file), "%s%s.desktop", 
                 desktop_paths[i], app_id);
        
        FILE *f = fopen(desktop_file, "r");
        if (f) {
            // Parse desktop file for Icon= line
            while (fgets(line, sizeof(line), f)) {
                if (strncmp(line, "Icon=", 5) == 0) {
                    char *icon = line + 5;
                    // Remove newline
                    char *newline = strchr(icon, '\n');
                    if (newline) *newline = '\0';
                    icon_name = strdup(icon);
                    break;
                }
            }
            fclose(f);
            
            if (icon_name) break;
        }
    }
    
    if (!icon_name) {
        return NULL;
    }
    
    // If icon is absolute path, return it
    if (icon_name[0] == '/') {
        return icon_name;
    }
    
    // Otherwise, search in icon theme directories
    const char *icon_paths[] = {
        "/usr/share/icons/hicolor/48x48/apps/",
        "/usr/share/icons/hicolor/scalable/apps/",
        "/usr/share/pixmaps/",
        NULL
    };
    
    const char *extensions[] = {".png", ".svg", ".xpm", ""};
    
    for (int i = 0; icon_paths[i]; i++) {
        for (int j = 0; extensions[j][0]; j++) {
            char full_path[512];
            snprintf(full_path, sizeof(full_path), "%s%s%s", 
                     icon_paths[i], icon_name, extensions[j]);
            
            FILE *test = fopen(full_path, "r");
            if (test) {
                fclose(test);
                free(icon_name);
                return strdup(full_path);
            }
        }
    }
    
    free(icon_name);
    return NULL;
} */

static void toplevel_handle_title(void *data,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle,
                                  const char *title) {
    struct toplevel_info *info = data;
    /* free(info->title);
    info->title = strdup(title); */
    printf("Toplevel title: %s\n", title);
}

static void toplevel_handle_app_id(void *data,
                                   struct zwlr_foreign_toplevel_handle_v1 *handle,
                                   const char *app_id) {
    struct toplevel_info *info = data;
    /* free(info->app_id);
    info->app_id = strdup(app_id);
    
    // Find icon for this app
    free(info->icon_path);
    info->icon_path = find_icon_for_app_id(app_id);
     */
    printf("Toplevel app_id: %s, icon: %s\n", app_id, "no" /* info->icon_path ? info->icon_path : "not found" */);
}

static void toplevel_handle_output_enter(void *data,
                                        struct zwlr_foreign_toplevel_handle_v1 *handle,
                                        struct wl_output *output) {
    // Handle output enter if needed
}

static void toplevel_handle_output_leave(void *data,
                                        struct zwlr_foreign_toplevel_handle_v1 *handle,
                                        struct wl_output *output) {
    // Handle output leave if needed
}

static void toplevel_handle_state(void *data,
                                 struct zwlr_foreign_toplevel_handle_v1 *handle,
                                 struct wl_array *state) {
    /* struct toplevel_info *info = data;
    info->state = 0;
    
    uint32_t *s;
    wl_array_for_each(s, state) {
        info->state |= *s;
    } */
}

static void toplevel_handle_done(void *data,
                                struct zwlr_foreign_toplevel_handle_v1 *handle) {
    // All events for this toplevel have been sent
}

static void toplevel_handle_closed(void *data,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle) {
    struct toplevel_info *info = data;
    
    printf("Toplevel closed: %s\n", info->app_id ? info->app_id : "unknown");
    
    // Remove from linked list
    struct toplevel_info **current = &toplevels;
    while (*current) {
        if (*current == info) {
            *current = info->next;
            break;
        }
        current = &(*current)->next;
    }
    
    // Cleanup
    free(info->app_id);
    free(info->title);
    zwlr_foreign_toplevel_handle_v1_destroy(info->handle);
    free(info);
}

static void toplevel_handle_parent(void *data,
                                  struct zwlr_foreign_toplevel_handle_v1 *handle,
                                  struct zwlr_foreign_toplevel_handle_v1 *parent) {
    // Handle parent relationship if needed
}

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

// Manager listeners
static void toplevel_manager_handle_toplevel(void *data,
                                            struct zwlr_foreign_toplevel_manager_v1 *manager,
                                            struct zwlr_foreign_toplevel_handle_v1 *handle) {
    struct toplevel_info *info = calloc(1, sizeof(struct toplevel_info));
    info->handle = handle;
    
    // Add to linked list
    info->next = toplevels;
    toplevels = info;
    
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_handle_listener, info);
}

static void toplevel_manager_handle_finished(void *data,
                                            struct zwlr_foreign_toplevel_manager_v1 *manager) {
    // Manager is no longer valid
    zwlr_foreign_toplevel_manager_v1_destroy(manager);
    toplevel_manager = NULL;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener toplevel_manager_listener = {
    .toplevel = toplevel_manager_handle_toplevel,
    .finished = toplevel_manager_handle_finished,
};

// Registry handler
static void toplevel_registry_handler(void *data, struct wl_registry *registry,
                                     uint32_t name, const char *interface,
                                     uint32_t version) {
    toplevel_manager = wl_registry_bind(registry, name,
                                       &zwlr_foreign_toplevel_manager_v1_interface, 3);
    zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_manager,
                                                 &toplevel_manager_listener, NULL);
}

// Public API
void toplevel_init(void) {
    registry_add_handler("zwlr_foreign_toplevel_manager_v1",toplevel_registry_handler, NULL);
}

void toplevel_cleanup(void) {
    // Clean up all toplevels
    while (toplevels) {
        struct toplevel_info *next = toplevels->next;
        free(toplevels->app_id);
        free(toplevels->title);
        zwlr_foreign_toplevel_handle_v1_destroy(toplevels->handle);
        free(toplevels);
        toplevels = next;
    }
    
    if (toplevel_manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(toplevel_manager);
        toplevel_manager = NULL;
    }
}

// Get list of open programs
toplevel_info *toplevel_get_list(void) {
    return toplevels;
}

// Helper to print all toplevels (for debugging)
void toplevel_print_all(void) {
    struct toplevel_info *info = toplevels;
    printf("\n=== Open Programs ===\n");
    while (info) {
        printf("App ID: %s\n", info->app_id ? info->app_id : "unknown");
        printf("Title: %s\n", info->title ? info->title : "unknown");
        printf("---\n");
        info = info->next;
    }
}