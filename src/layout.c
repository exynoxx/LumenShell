#include "layout.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static dk_ui_element* allocate_element(dk_ui_manager *mgr) {
    if (mgr->element_count >= MAX_UI_ELEMENTS) {
        return NULL;
    }
    dk_ui_element *elem = &mgr->elements[mgr->element_count++];
    memset(elem, 0, sizeof(dk_ui_element));
    return elem;
}

static void add_child(dk_ui_element *parent, dk_ui_element *child) {
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

void dk_ui_init(dk_ui_manager *mgr, dk_context *ctx) {
    memset(mgr, 0, sizeof(dk_ui_manager));
    mgr->ctx = ctx;
}

void dk_ui_reset(dk_ui_manager *mgr) {
    mgr->element_count = 0;
    mgr->root = NULL;
    mgr->current_parent = NULL;
}

void dk_ui_start_box(dk_ui_manager *mgr, int width, int height) {
    dk_ui_element *box = allocate_element(mgr);
    if (!box) return;
    
    box->type = ELEMENT_BOX;
    

    box->data.style.padding_top = 0;
    box->data.style.padding_right = 0;
    box->data.style.padding_bottom = 0;
    box->data.style.padding_left = 0;
    box->data.style.gap = 0;
    box->data.style.float_mode = 0;

    if (mgr->current_parent) {

        box->width = (width <= 0) ? mgr->current_parent->width : width;
        box->height = (height <= 0) ? mgr->current_parent->height : height;

        add_child(mgr->current_parent, box);
    } else {

        box->width = (width <= 0) ? mgr->ctx->screen_width : width;
        box->height = (height <= 0) ? mgr->ctx->screen_height: height;

        mgr->root = box;
    }
    
    mgr->current_parent = box;
}

void dk_ui_box_set_padding(dk_ui_manager *mgr, int top, int right, int bottom, int left) {
    if (!mgr->current_parent || mgr->current_parent->type != ELEMENT_BOX) return;
    mgr->current_parent->data.style.padding_top = top;
    mgr->current_parent->data.style.padding_right = right;
    mgr->current_parent->data.style.padding_bottom = bottom;
    mgr->current_parent->data.style.padding_left = left;
}

void dk_ui_box_set_gap(dk_ui_manager *mgr, int gap) {
    if (!mgr->current_parent || mgr->current_parent->type != ELEMENT_BOX) return;
    mgr->current_parent->data.style.gap = gap;
}

void dk_ui_box_float(dk_ui_manager *mgr, dk_float_mode float_mode){
    if (!mgr->current_parent || mgr->current_parent->type != ELEMENT_BOX) return;
    mgr->current_parent->data.style.float_mode = float_mode;
}

void dk_ui_end_box(dk_ui_manager *mgr) {
    if (!mgr->current_parent) return;
    mgr->current_parent = mgr->current_parent->parent;
}

void dk_ui_rect(dk_ui_manager *mgr, int width, int height, dk_color color) {
    if (!mgr->current_parent) return;
    
    dk_ui_element *rect = allocate_element(mgr);
    if (!rect) return;
    
    rect->type = ELEMENT_RECT;
    rect->width = width;
    rect->height = height;
    rect->data.color = color;

    add_child(mgr->current_parent, rect);
}

/* void dk_ui_rounded_rect(dk_ui_manager *mgr, float width, float height, float radius) {
    if (!mgr->current_parent) return;
    
    dk_ui_element *rect = allocate_element(mgr);
    if (!rect) return;
    
    rect->type = ELEMENT_ROUNDED_RECT;
    rect->width = width;
    rect->height = height;
    rect->r = mgr->current_r;
    rect->g = mgr->current_g;
    rect->b = mgr->current_b;
    rect->a = mgr->current_a;
    rect->data.rounded_rect.radius = radius;
    
    add_child(mgr->current_parent, rect);
} */

void dk_ui_texture(dk_ui_manager *mgr, GLuint texture_id, int width, int height) {
    if (!mgr->current_parent) return;
    
    dk_ui_element *tex = allocate_element(mgr);
    if (!tex) return;
    
    tex->type = ELEMENT_TEXTURE;
    tex->width = width;
    tex->height = height;
    tex->data.texture_id = texture_id;
    
    add_child(mgr->current_parent, tex);
}

// Layout calculation - recursive function to position all children
static void calculate_layout(dk_ui_element *elem, float parent_x, float parent_y) {
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
        
        dk_ui_element *child = elem->first_child;

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
                        
                        calculate_layout(child, content_x, content_y);
                        content_x += child->width + style->gap;
                        if (child->height > max_line_height) {
                            max_line_height = child->height;
                        }
                        break;
                        
                    case FLOAT_NONE:
                        // For absolute, children define their own position
                        calculate_layout(child, content_x, content_y);
                        break;
                }
            }
            child = child->next_sibling;
        }
    }
        
}

static void draw_element(dk_ui_manager *mgr, dk_ui_element *elem) {
    if (!elem) return;
    
    switch (elem->type) {
        case ELEMENT_RECT:
            dk_set_color(mgr->ctx, elem->data.color);
            dk_draw_rect(mgr->ctx, elem->x, elem->y, elem->width, elem->height);
            break;
            
        case ELEMENT_TEXTURE:
            dk_draw_texture(mgr->ctx, elem->data.texture_id, elem->x, elem->y, elem->width, elem->height);
            break;
            
        case ELEMENT_BOX:

            // Draw all children
            dk_ui_element *child = elem->first_child;
            while (child) {
                draw_element(mgr, child);
                child = child->next_sibling;
            }

            break;
    }
    
    
}

void dk_ui_draw(dk_ui_manager *mgr, int root_x, int root_y) {
    if (!mgr->root) return;
    
    // First pass: calculate all positions
    calculate_layout(mgr->root, root_x, root_y);
    
    // Second pass: draw everything
    draw_element(mgr, mgr->root);
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