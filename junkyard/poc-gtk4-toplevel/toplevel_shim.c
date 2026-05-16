/* Minimal shim: binds zwlr_foreign_toplevel_manager_v1 onto an existing
 * wl_display (the one owned by GDK) and feeds events back via callbacks.
 *
 * Reuses the wayland-scanner-generated protocol files already shipped in
 * ../wlhooks/generated/. No event loop is started here — GDK owns the
 * dispatch on the shared wl_display.
 */

#define _POSIX_C_SOURCE 200809L
#include "toplevel_shim.h"
#include "../wlhooks/generated/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#define WLR_TOPLEVEL_MAX_VERSION 3

typedef struct entry_node {
    toplevel_entry           pub;
    struct entry_node       *next;
    bool                     pending_app_id;
    bool                     pending_title;
    bool                     pending_state;
} entry_node;

static struct {
    struct wl_registry                       *registry;
    struct zwlr_foreign_toplevel_manager_v1  *manager;
    entry_node                               *head;
    uint32_t                                  next_id;
    toplevel_added_cb                         added;
    toplevel_changed_cb                       changed;
    toplevel_closed_cb                        closed;
    void                                     *user;
    bool                                      announced[1024];
} S;

static void list_prepend (entry_node *n) { n->next = S.head; S.head = n; }

static void list_remove (entry_node *n) {
    entry_node **pp = &S.head;
    while (*pp && *pp != n) pp = &(*pp)->next;
    if (*pp) *pp = n->next;
}

/* --- handle listener --- */

static void h_title (void *data, struct zwlr_foreign_toplevel_handle_v1 *h, const char *title) {
    (void)h; entry_node *n = data;
    free(n->pub.title);
    n->pub.title = title ? strdup(title) : NULL;
    n->pending_title = true;
}

static void h_app_id (void *data, struct zwlr_foreign_toplevel_handle_v1 *h, const char *app_id) {
    (void)h; entry_node *n = data;
    free(n->pub.app_id);
    n->pub.app_id = app_id ? strdup(app_id) : NULL;
    n->pending_app_id = true;
}

static void h_state (void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_array *state) {
    (void)h; entry_node *n = data;
    bool activated = false;
    uint32_t *p;
    wl_array_for_each(p, state) {
        if (*p == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED) { activated = true; break; }
    }
    n->pub.activated = activated;
    n->pending_state = true;
}

static void h_done (void *data, struct zwlr_foreign_toplevel_handle_v1 *h) {
    (void)h; entry_node *n = data;
    if (!S.announced[n->pub.id & 1023]) {
        S.announced[n->pub.id & 1023] = true;
        if (S.added)   S.added(&n->pub, S.user);
    } else {
        if (S.changed) S.changed(&n->pub, S.user);
    }
    n->pending_title = n->pending_app_id = n->pending_state = false;
}

static void h_closed (void *data, struct zwlr_foreign_toplevel_handle_v1 *h) {
    entry_node *n = data;
    if (S.closed) S.closed(n->pub.id, S.user);
    zwlr_foreign_toplevel_handle_v1_destroy(h);
    list_remove(n);
    S.announced[n->pub.id & 1023] = false;
    free(n->pub.app_id);
    free(n->pub.title);
    free(n);
}

static void h_output_enter (void *d, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) { (void)d;(void)h;(void)o; }
static void h_output_leave (void *d, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) { (void)d;(void)h;(void)o; }
static void h_parent       (void *d, struct zwlr_foreign_toplevel_handle_v1 *h,
                            struct zwlr_foreign_toplevel_handle_v1 *p)            { (void)d;(void)h;(void)p; }

static const struct zwlr_foreign_toplevel_handle_v1_listener handle_listener = {
    .title         = h_title,
    .app_id        = h_app_id,
    .output_enter  = h_output_enter,
    .output_leave  = h_output_leave,
    .state         = h_state,
    .done          = h_done,
    .closed        = h_closed,
    .parent        = h_parent,
};

/* --- manager listener --- */

static void m_toplevel (void *data, struct zwlr_foreign_toplevel_manager_v1 *mgr,
                        struct zwlr_foreign_toplevel_handle_v1 *h) {
    (void)data; (void)mgr;
    entry_node *n = calloc(1, sizeof *n);
    n->pub.id     = ++S.next_id;
    n->pub.handle = h;
    list_prepend(n);
    zwlr_foreign_toplevel_handle_v1_add_listener(h, &handle_listener, n);
}

static void m_finished (void *data, struct zwlr_foreign_toplevel_manager_v1 *mgr) {
    (void)data; (void)mgr;
    if (S.manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(S.manager);
        S.manager = NULL;
    }
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = m_toplevel,
    .finished = m_finished,
};

/* --- registry --- */

static void r_global (void *data, struct wl_registry *reg, uint32_t name,
                      const char *iface, uint32_t version) {
    (void)data;
    if (strcmp(iface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        uint32_t v = version < WLR_TOPLEVEL_MAX_VERSION ? version : WLR_TOPLEVEL_MAX_VERSION;
        S.manager = wl_registry_bind(reg, name,
            &zwlr_foreign_toplevel_manager_v1_interface, v);
        zwlr_foreign_toplevel_manager_v1_add_listener(S.manager,
            &manager_listener, NULL);
    }
}

static void r_global_remove (void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global        = r_global,
    .global_remove = r_global_remove,
};

/* --- public API --- */

int toplevel_shim_init (struct wl_display *display,
                        toplevel_added_cb   added,
                        toplevel_changed_cb changed,
                        toplevel_closed_cb  closed,
                        void               *user) {
    if (!display) return -1;
    S.added = added; S.changed = changed; S.closed = closed; S.user = user;
    S.registry = wl_display_get_registry(display);
    if (!S.registry) return -1;
    wl_registry_add_listener(S.registry, &registry_listener, NULL);
    return 0;
}

void toplevel_shim_finish_setup (struct wl_display *display) {
    /* Two roundtrips: first delivers the registry globals (bind manager),
     * second delivers the manager's toplevel events + per-handle metadata.
     * Only call at startup; afterwards GDK pumps events on the same fd. */
    wl_display_roundtrip(display);
    wl_display_roundtrip(display);
}

void toplevel_shim_destroy (void) {
    if (S.manager)  { zwlr_foreign_toplevel_manager_v1_destroy(S.manager);  S.manager = NULL; }
    if (S.registry) { wl_registry_destroy(S.registry);                       S.registry = NULL; }
    entry_node *n = S.head;
    while (n) { entry_node *nx = n->next; free(n->pub.app_id); free(n->pub.title); free(n); n = nx; }
    S.head = NULL;
}
