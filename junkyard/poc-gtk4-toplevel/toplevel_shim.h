#pragma once

#include <stdbool.h>
#include <stdint.h>

struct wl_display;

typedef struct toplevel_entry {
    uint32_t  id;
    char     *app_id;
    char     *title;
    bool      activated;
    void     *handle;
} toplevel_entry;

typedef void (*toplevel_added_cb)  (const toplevel_entry *e, void *user);
typedef void (*toplevel_changed_cb)(const toplevel_entry *e, void *user);
typedef void (*toplevel_closed_cb) (uint32_t id,             void *user);

int  toplevel_shim_init (struct wl_display *display,
                         toplevel_added_cb   added,
                         toplevel_changed_cb changed,
                         toplevel_closed_cb  closed,
                         void               *user);

void toplevel_shim_finish_setup (struct wl_display *display);
void toplevel_shim_destroy      (void);
