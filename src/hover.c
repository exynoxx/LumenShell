#include "hover.h"
#include <stdlib.h>

static int inside(dk_ui_node *o, int px, int py) {
    return (px >= o->x && px <= o->x + o->width &&
            py >= o->y && py <= o->y + o->height);
}
/* 
void hit_add(dk_context *ctx, dk_ui_node *node, bool *hover) {
    dk_hitbox_mngr mngr = ctx->hitbox_mngr;

    if (mngr.idx >= mngr.capacity)
        return; // full


    dk_hitbox *o = &mngr.hitboxes[mngr.count++];
    o->node = node;
    o->hover = hover;
} */

/* int hit_query(dk_context *ctx, int px, int py) {

    dk_hitbox_mngr r = ctx->hitbox_mngr;
    int hit_any = 0;

    // Reset all hover flags
    for (int i = 0; i < r.count; i++) {
        if (r.hitboxes[i].hover)
            *(r.hitboxes[i].hover) = false;
    }

    // Find the first that matches
    for (int i = 0; i < r.count; i++) {
        dk_hitbox *o = &r.hitboxes[i];
        if (inside(o->node, px, py)) {
            if (o->hover) //TODO guard on registration
                *(o->hover) = true;
            hit_any = 1;
            break; // stop after first match
        }
    }

    return hit_any;
} */
int hit_query(dk_context *ctx, int px, int py) {
    int hit_any = 0;

    for (int i = 0; i < ctx->node_mngr.element_count; i++) {
        ctx->node_mngr.nodes[i].hovered = false;
    }

    for (int i = 0; i < ctx->node_mngr.element_count; i++) {
        dk_ui_node *o = &ctx->node_mngr.nodes[i];
        if (inside(o, px, py)) {
            o->hovered = true;
            hit_any = 1;
        }
    }

    return hit_any;
}
