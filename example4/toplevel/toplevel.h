#ifndef TOPLEVEL_H
#define TOPLEVEL_H

#include <stdlib.h>
#include "../wayland_protocols/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

void toplevel_cleanup(void);
void toplevel_focus_window(const char* app_id, const char* title);

#endif