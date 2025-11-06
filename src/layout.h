#ifndef LAYOUT_H
#define LAYOUT_H

#include <stdbool.h>
#include "draw.h"
#include "texture.h"

// Forward declaration

// Layout types
typedef enum {
    FLOAT_LEFT,
    FLOAT_NONE
} dk_float_mode;

// Element types
typedef enum {
    ELEMENT_BOX,
    ELEMENT_RECT,
    //ELEMENT_ROUNDED_RECT,
    ELEMENT_TEXTURE
} dk_element_type;

// Alignment options
/* typedef enum {
    ALIGN_START,
    ALIGN_CENTER,
    ALIGN_END,
    ALIGN_SPACE_BETWEEN,
    ALIGN_SPACE_AROUND
} dk_alignment; */

// Box style properties
typedef struct {
    int padding_top;
    int padding_right;
    int padding_bottom;
    int padding_left;
    int gap;              // Space between children
    dk_float_mode float_mode;
} dk_box_style;

// Element data unions
/*typedef struct {
    float radius;
} dk_rounded_rect_data;
 */
/* 
typedef struct {
    GLuint texture_id;
} dk_texture_data;
 */
/* typedef struct {
    dk_layout_type layout_type;
    dk_box_style style;
} dk_box_data; */

// UI Element (node in the tree)
typedef struct dk_ui_element {
    dk_element_type type;
    
    float width;
    float height;
    
    float x;
    float y;
    
    union {
        dk_box_style style;
        GLuint texture_id;
        dk_color color;
    } data;
    
    // Tree structure
    struct dk_ui_element *parent;
    struct dk_ui_element *first_child;
    struct dk_ui_element *last_child;
    struct dk_ui_element *next_sibling;
} dk_ui_element;

// Maximum elements
#define MAX_UI_ELEMENTS 4096

// UI Manager
typedef struct {
    dk_ui_element elements[MAX_UI_ELEMENTS];
    int element_count;
    dk_ui_element *root;
    dk_ui_element *current_parent;
    dk_context *ctx;
} dk_ui_manager;

void dk_ui_init(dk_ui_manager *mgr, dk_context *ctx);
void dk_ui_reset(dk_ui_manager *mgr);

void dk_ui_start_box(dk_ui_manager *mgr, int width, int height);

void dk_ui_box_set_padding(dk_ui_manager *mgr, int top, int right, int bottom, int left);
void dk_ui_box_set_gap(dk_ui_manager *mgr, int gap);
void dk_ui_box_float(dk_ui_manager *mgr, dk_float_mode float_mode);

void dk_ui_end_box(dk_ui_manager *mgr);

void dk_ui_rect(dk_ui_manager *mgr, int width, int height, dk_color color);
//void dk_ui_rounded_rect(dk_ui_manager *mgr, int width, int height, int radius);
void dk_ui_texture(dk_ui_manager *mgr, GLuint texture_id, int width, int height);

void dk_ui_draw(dk_ui_manager *mgr, int root_x, int root_y);

#endif