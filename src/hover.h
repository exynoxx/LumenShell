#ifndef HOVER_H
#define HOVER_H

#include "structures.h"

//void hit_add(dk_context *ctx, dk_ui_node *node, bool *hover);
int dk_hitbox_query(dk_context *ctx, int px, int py);

#endif
