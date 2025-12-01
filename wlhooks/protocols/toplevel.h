#ifndef TOPLEVEL_H
#define TOPLEVEL_H

#include <stdlib.h>
#include "../generated/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

typedef void (*toplevel_window_new)(const char* app_id, const char* title, void* user_data);
typedef void (*toplevel_window_rm)(const char* app_id, const char* title, void* user_data);
typedef void (*toplevel_window_focus)(const char* app_id, const char* title, void* user_data);

void toplevel_init(void);
void toplevel_cleanup(void);
void register_on_window_new(toplevel_window_new cb, void* user_data);
void register_on_window_rm(toplevel_window_rm cb, void* user_data);
void register_on_window_focus(toplevel_window_focus cb, void* user_data);

void toplevel_activate_by_id(const char* app_id, const char* title);
void toplevel_minimize_by_id(const char* app_id, const char* title);

#endif