#ifndef HOVER_H
#define HOVER_H

#include "structures.h"

void dk_hover_reset(dk_context *ctx);
int dk_hover_query(dk_context *ctx, int px, int py, bool clicked);

void dk_register_on_hover(dk_ui_node *node, dk_on_hover cb, void* user_data);
void dk_register_on_clicked(dk_ui_node *node, dk_on_clicked cb, void* user_data);
#endif
