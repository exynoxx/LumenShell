#ifndef REGISTRY_H
#define REGISTRY_H

#include <wayland-client.h>

typedef void (*registry_handler_fn)(void *data, struct wl_registry *registry,
                                     uint32_t name, const char *interface, 
                                     uint32_t version);

typedef void (*registry_remover_fn)(void *data, struct wl_registry *registry,
                                    uint32_t name);

void registry_add_handler(const char *interface_name,
                          registry_handler_fn handler,
                          void *user_data);

// Optionally attach a remover callback for an already-registered interface.
// Called when the compositor sends global_remove for that interface name.
void registry_set_remover(const char *interface_name, registry_remover_fn remover);

void registry_init(struct wl_display *display);
void registry_cleanup(void);

#endif // REGISTRY_H