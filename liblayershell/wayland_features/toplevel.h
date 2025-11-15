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

void toplevel_init();
void toplevel_cleanup();

toplevel_info *toplevel_get_list();
void toplevel_print_all();

#endif