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
    // Tell the compositor where this window is represented on screen (its
    // taskbar button), relative to `surface`. Used as the minimize-animation
    // target (e.g. Wayfire's squeezimize). Optional — NULL when the backend's
    // protocol can't express it (the ext-foreign-toplevel list can't).
    void (*set_rectangle)(toplevel_window_t *w, struct wl_surface *surface,
                          int32_t x, int32_t y, int32_t width, int32_t height);
    void (*destroy_handle)(toplevel_window_t *w); // tear down protocol handle
} toplevel_window_ops_t;

struct toplevel_window {
    uint32_t id;
    char    *app_id;
    char    *title;
    char    *output;                       // last-entered output connector, or NULL
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
void window_list_set_output   (toplevel_window_t *w, const char *output_name, bool entered);
void window_list_destroy      (toplevel_window_t *w); // remove + free + emit rm cb

// Public callback registration (re-exported via toplevel.h).
void window_list_register_new  (toplevel_window_new   cb, void *user_data);
void window_list_register_rm   (toplevel_window_rm    cb, void *user_data);
void window_list_register_focus(toplevel_window_focus cb, void *user_data);
void window_list_register_output(toplevel_window_output cb, void *user_data);

#endif
