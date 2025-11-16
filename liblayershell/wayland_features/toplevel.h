#ifndef TOPLEVEL_H
#define TOPLEVEL_H

#include <stdlib.h>
#include "../wayland_protocols/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

typedef struct toplevel_info {
    char *app_id;
    char *title;
    uint32_t state;
    struct toplevel_info *next;
    struct zwlr_foreign_toplevel_handle_v1 *handle;
} toplevel_info;

typedef void (*toplevel_window_new)(const char *app_id, const char *title, void *user_data);
typedef void (*toplevel_window_remove)(const char *app_id, const char *title, void *user_data);

void toplevel_init();
void toplevel_cleanup();

toplevel_info *toplevel_get_list();
void toplevel_print_all();

void register_on_window_new(toplevel_window_new cb, void *user_data);
void register_on_window_rm(toplevel_window_remove cb, void *user_data);

#endif