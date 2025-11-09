#include "layout.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "hover.h"
#include "backend.h"

static dk_ui_node* allocate_element(dk_context *ctx) {
    if (ctx->node_mngr.element_count >= MAX_UI_ELEMENTS) {
        return NULL;
    }
    dk_ui_node *elem = &ctx->node_mngr.nodes[ctx->node_mngr.element_count++];
    memset(elem, 0, sizeof(dk_ui_node));
    return elem;
}

static void add_child(dk_ui_node *parent, dk_ui_node *child) {
    child->parent = parent;
    child->next_sibling = NULL;
    
    if (parent->last_child) {
        parent->last_child->next_sibling = child;
        parent->last_child = child;
    } else {
        parent->first_child = child;
        parent->last_child = child;
    }
}

void dk_ui_reset(dk_context *ctx){
    ctx->node_mngr.element_count = 0;
    ctx->node_mngr.current_parent = NULL;
    ctx->node_mngr.root = NULL;
}

void dk_ui_start_box(dk_context *ctx, int width, int height) {
    dk_ui_node *box = allocate_element(ctx);
    if (!box) return;
    
    box->type = ELEMENT_BOX;
    box->data.style.padding_top = 0;
    box->data.style.padding_right = 0;
    box->data.style.padding_bottom = 0;
    box->data.style.padding_left = 0;
    box->data.style.gap = 0;
    box->data.style.float_mode = 0;

    if (ctx->node_mngr.current_parent) {

        box->width = (width <= 0) ? ctx->node_mngr.current_parent->width : width;
        box->height = (height <= 0) ? ctx->node_mngr.current_parent->height : height;

        add_child(ctx->node_mngr.current_parent, box);
    } else {

        box->width = (width <= 0) ? ctx->screen_width : width;
        box->height = (height <= 0) ? ctx->screen_height: height;

        ctx->node_mngr.root = box;
    }
    
    ctx->node_mngr.current_parent = box;
}

void dk_ui_box_set_padding(dk_context *ctx, int top, int right, int bottom, int left) {
    if (!ctx->node_mngr.current_parent || ctx->node_mngr.current_parent->type != ELEMENT_BOX) return;
    ctx->node_mngr.current_parent->data.style.padding_top = top;
    ctx->node_mngr.current_parent->data.style.padding_right = right;
    ctx->node_mngr.current_parent->data.style.padding_bottom = bottom;
    ctx->node_mngr.current_parent->data.style.padding_left = left;
}

void dk_ui_box_set_gap(dk_context *ctx, int gap) {
    if (!ctx->node_mngr.current_parent || ctx->node_mngr.current_parent->type != ELEMENT_BOX) return;
    ctx->node_mngr.current_parent->data.style.gap = gap;
}

void dk_ui_box_float(dk_context *ctx, dk_float_mode float_mode){
    if (!ctx->node_mngr.current_parent || ctx->node_mngr.current_parent->type != ELEMENT_BOX) return;
    ctx->node_mngr.current_parent->data.style.float_mode = float_mode;
}

void dk_ui_end_box(dk_context *ctx) {
    if (!ctx->node_mngr.current_parent || ctx->node_mngr.current_parent == ctx->node_mngr.root) return;
    ctx->node_mngr.current_parent = ctx->node_mngr.current_parent->parent;
}

dk_ui_node *dk_ui_rect(dk_context *ctx, int width, int height, dk_color color) {
    if (!ctx->node_mngr.current_parent) return NULL;
    
    dk_ui_node *rect = allocate_element(ctx);
    if (!rect) return NULL;
    
    rect->type = ELEMENT_RECT;
    rect->width = width;
    rect->height = height;
    rect->data.color = color;

    add_child(ctx->node_mngr.current_parent, rect);
    return rect;
}

/* void dk_ui_rounded_rect(dk_context *ctx, float width, float height, float radius) {
    if (!ctx->node_mngr.current_parent) return;
    
    dk_ui_node *rect = allocate_element(mgr);
    if (!rect) return;
    
    rect->type = ELEMENT_ROUNDED_RECT;
    rect->width = width;
    rect->height = height;
    rect->r = ctx->node_mngr.current_r;
    rect->g = ctx->node_mngr.current_g;
    rect->b = ctx->node_mngr.current_b;
    rect->a = ctx->node_mngr.current_a;
    rect->data.rounded_rect.radius = radius;
    
    add_child(ctx->node_mngr.current_parent, rect);
} */

dk_ui_node *dk_ui_texture(dk_context *ctx, GLuint texture_id, int width, int height) {
    if (!ctx->node_mngr.current_parent) return NULL;
    
    dk_ui_node *tex = allocate_element(ctx);
    if (!tex) return NULL;
    
    tex->type = ELEMENT_TEXTURE;
    tex->width = width;
    tex->height = height;
    tex->data.texture_id = texture_id;
    
    add_child(ctx->node_mngr.current_parent, tex);
    return tex;
}

// Layout calculation - recursive function to position all children
void evaluate_positions(dk_ui_node *elem, float parent_x, float parent_y) {
    if (!elem) return;
    
    // Set element's absolute position
    elem->x = parent_x;
    elem->y = parent_y;

    if(elem->width <= 0) elem->width = elem->parent->width;
    if(elem->height <= 0) elem->height = elem->parent->height;
    
    if (elem->type == ELEMENT_BOX) {
        dk_box_style *style = &elem->data.style;
        
        float content_x = elem->x + style->padding_left;
        float content_y = elem->y + style->padding_top;
        float max_line_height = 0;
        float line_start_x = content_x;
        
        float available_width = elem->width - style->padding_left - style->padding_right;
        float available_height = elem->height - style->padding_top - style->padding_bottom;
        
        dk_ui_node *child = elem->first_child;

        if(elem->type == ELEMENT_BOX){
            while (child) {
                switch (elem->data.style.float_mode) {
                    case FLOAT_LEFT:
                        // Check if we need to wrap
                        if (content_x + child->width > elem->x + elem->width - style->padding_right && 
                            content_x > line_start_x) {
                            content_y += max_line_height + style->gap;
                            content_x = line_start_x;
                            max_line_height = 0;
                        }
                        
                        evaluate_positions(child, content_x, content_y);
                        content_x += child->width + style->gap;
                        if (child->height > max_line_height) {
                            max_line_height = child->height;
                        }
                        break;
                        
                    case FLOAT_NONE:
                        // For absolute, children define their own position
                        evaluate_positions(child, content_x, content_y);
                        break;
                }
                child = child->next_sibling;
            }
        }
    }
        
}

static void draw_element(dk_context *ctx, dk_ui_node *elem) {
    if (!elem) return;
    
    switch (elem->type) {
        case ELEMENT_RECT:
            dk_draw_rect(ctx, elem->x, elem->y, elem->width, elem->height, elem->data.color);
            break;
            
        case ELEMENT_TEXTURE:
            dk_draw_texture(ctx, elem->data.texture_id, elem->x, elem->y, elem->width, elem->height);
            break;
            
        case ELEMENT_BOX:

            // Draw all children
            dk_ui_node *child = elem->first_child;
            while (child) {
                draw_element(ctx, child);
                child = child->next_sibling;
            }

            break;
    }
}

void dk_ui_draw(dk_context *ctx, int root_x, int root_y) {
    if (!ctx->node_mngr.root) return;
    
    // First pass: calculate all positions
    evaluate_positions(ctx->node_mngr.root, root_x, root_y);
    
    // Second pass: draw everything
    draw_element(ctx, ctx->node_mngr.root);
}

// Example usage:
/*
dk_ui_manager ui;
dk_ui_init(&ui, ctx);

dk_begin_frame(ctx);

// Build UI hierarchy
dk_ui_start_box(&ui, LAYOUT_FLOAT_LEFT, 500, 300);
dk_ui_box_set_padding(&ui, 10, 10, 10, 10);
dk_ui_box_set_gap(&ui, 5);

    dk_ui_set_color(&ui, 1, 0, 0, 1);
    dk_ui_rect(&ui, 50, 50);
    
    dk_ui_set_color(&ui, 0, 1, 0, 1);
    dk_ui_rect(&ui, 50, 50);
    
    dk_ui_set_color(&ui, 0, 0, 1, 1);
    dk_ui_rect(&ui, 50, 50);

dk_ui_end_box(&ui);

// Calculate positions and draw
dk_ui_draw(&ui, 10, 10);

// Reset for next frame
dk_ui_reset(&ui);

dk_end_frame();
*/