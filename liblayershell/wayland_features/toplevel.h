#ifndef TOPLEVEL_H
#define TOPLEVEL_H

#include <stdlib.h>
#include "../wayland_protocols/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

struct toplevel_info {
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *app_id;
    char *title;
    char *icon_path;
    uint32_t state;
    struct toplevel_info *next;
};

void toplevel_init();
void toplevel_cleanup();

struct toplevel_info *toplevel_get_list();
void toplevel_print_all();

#endif