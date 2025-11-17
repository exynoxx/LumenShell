#include "hover.h"
#include <stdlib.h>

void dk_register_on_hover(dk_ui_node *node, dk_on_hover cb, void* user_data)
{
    node->hoverable->cb_on_hover = cb;
    node->hoverable->on_hover_user_data = user_data;
}

void dk_register_on_clicked(dk_ui_node *node, dk_on_clicked cb, void* user_data){
    node->hoverable->cb_on_clicked = cb;
    node->hoverable->on_clicked_user_data = user_data;
}

static int inside(dk_ui_node *o, int px, int py) {
    return (px >= o->x && px <= o->x + o->width &&
            py >= o->y && py <= o->y + o->height);
}

void dk_hover_reset(dk_context *ctx){
    for (int i = 0; i < ctx->hitbox_mngr.count; i++) {
        ctx->hitbox_mngr.elements[i].hovered = false;
        ctx->hitbox_mngr.elements[i].down = false;
    }
}

int dk_hover_query(dk_context *ctx, int px, int py, bool clicked) {
    int hit_any = 0;

    for (int i = 0; i < ctx->hitbox_mngr.count; i++) {
        dk_ui_node *e = &ctx->node_mngr.nodes[i];
        if (inside(e, px, py)) {
            hit_any = 1;
            
            if(e->hoverable->cb_on_hover && !e->hoverable->hovered){
                e->hoverable->cb_on_hover(e, e->hoverable->on_hover_user_data);
            }
            e->hoverable->hovered = true;
            
            if(e->hoverable->cb_on_clicked && !e->hoverable->down && clicked){
                e->hoverable->cb_on_clicked(e, e->hoverable->on_clicked_user_data);
            }
            e->hoverable->down = clicked;

        } else {
            e->hoverable->hovered = false;
            e->hoverable->down = false;
        }
    }

    return hit_any;
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