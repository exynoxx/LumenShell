#ifndef WINDOW_LIST_H
#define WINDOW_LIST_H

#include "toplevel.h"
#include <stdint.h>
#include <stdbool.h>
#include <wayland-client.h>

typedef struct toplevel_window toplevel_window_t;

// Per-window vtable. The backend creating a window installs the ops it
// supports; missing operations are reported as "not supported" by the public
// toplevel API rather than fatal.
typedef struct {
    void (*activate)(toplevel_window_t *w);
    void (*minimize)(toplevel_window_t *w);
    void (*close)   (toplevel_window_t *w);
    void (*destroy_handle)(toplevel_window_t *w); // tear down protocol handle
} toplevel_window_ops_t;

struct toplevel_window {
    uint32_t id;
    char    *app_id;
    char    *title;
    bool     activated;
    bool     announced;
    void    *handle;                       // backend-owned protocol object
    const toplevel_window_ops_t *ops;
    struct wl_list link;
};

void window_list_init(void);
void window_list_cleanup(void);

toplevel_window_t *window_list_create(void *handle, const toplevel_window_ops_t *ops);
toplevel_window_t *window_list_find(uint32_t id);

// Mutators — handle the "if announced AND data complete, fire callbacks"
// semantics so backends don't repeat them.
void window_list_set_title    (toplevel_window_t *w, const char *title);
void window_list_set_app_id   (toplevel_window_t *w, const char *app_id);
void window_list_emit_done    (toplevel_window_t *w);
void window_list_set_activated(toplevel_window_t *w, bool activated);
void window_list_destroy      (toplevel_window_t *w); // remove + free + emit rm cb

// Public callback registration (re-exported via toplevel.h).
void window_list_register_new  (toplevel_window_new   cb, void *user_data);
void window_list_register_rm   (toplevel_window_rm    cb, void *user_data);
void window_list_register_focus(toplevel_window_focus cb, void *user_data);

#endif
