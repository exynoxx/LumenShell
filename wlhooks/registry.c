#include "registry.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define MAX_HANDLERS 32

typedef struct {
    char *interface_name;
    registry_handler_fn handler;
    void *user_data;
} registry_handler;

static registry_handler handlers[MAX_HANDLERS];
static int handler_count = 0;
static struct wl_registry *global_registry = NULL;

void registry_add_handler(const char *interface_name,
                         registry_handler_fn handler,
                         void *user_data) {
    if (handler_count >= MAX_HANDLERS) return;
    
    handlers[handler_count].interface_name = strdup(interface_name);
    handlers[handler_count].handler = handler;
    handlers[handler_count].user_data = user_data;
    handler_count++;
}

static void registry_global(void *data, struct wl_registry *registry,
                           uint32_t name, const char *interface, 
                           uint32_t version) {
    for (int i = 0; i < handler_count; i++) {
        if (strcmp(interface, handlers[i].interface_name) == 0) {
            printf("registry hit for %s\n", interface);
            handlers[i].handler(handlers[i].user_data, registry, name, interface, version);
            return;
        }
    }

    //fprintf(stderr, "registry strcmp miss for %s\n", interface);
}

static void registry_global_remove(void *data, struct wl_registry *registry,uint32_t name) {
    // Handle removal if needed
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

void registry_init(struct wl_display *display) {
    global_registry = wl_display_get_registry(display);
    wl_registry_add_listener(global_registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
}

void registry_cleanup(void) {
    for (int i = 0; i < handler_count; i++) {
        free(handlers[i].interface_name);
    }
    handler_count = 0;
    
    if (global_registry) {
        wl_registry_destroy(global_registry);
        global_registry = NULL;
    }
}