#ifndef STRUCTURES_H
#define STRUCTURES_H

#include <GLES2/gl2.h>
#include <stdbool.h>

#define MAX_UI_ELEMENTS 4096

typedef struct {
    float r, g, b, a;
} dk_color;

typedef enum {
    FLOAT_LEFT,
    FLOAT_NONE
} dk_float_mode;

typedef enum {
    ELEMENT_BOX,
    ELEMENT_RECT,
    //ELEMENT_ROUNDED_RECT,
    ELEMENT_TEXTURE
} dk_node_type;

typedef struct {
    int gap;              // Space between children
    dk_float_mode float_mode;
} dk_box_style;

typedef struct dk_ui_node {
    dk_node_type type;
    
    float width;
    float height;
    
    float x;
    float y;

    int padding_top;
    int padding_right;
    int padding_left;
    
    union {
        dk_box_style style;
        GLuint texture_id;
        dk_color color;
    } data;

    bool hovered;
    
    struct dk_ui_node *parent;
    struct dk_ui_node *first_child;
    struct dk_ui_node *last_child;
    struct dk_ui_node *next_sibling;
} dk_ui_node;

typedef struct {
    dk_ui_node *nodes;
    int element_count;
    dk_ui_node *root;
    dk_ui_node *current_parent;
} dk_node_mngr;
/* 
typedef struct {
    dk_ui_node *node;
    bool *hover;
} dk_hitbox;

typedef struct {
    dk_hitbox *hitboxes;
    int count;
    int capacity;
} dk_hitbox_mngr; */

typedef struct {
    GLuint shader_program;
    GLuint rounded_rect_program;
    GLuint texture_program;
    GLuint vbo, vao;
    int screen_width;
    int screen_height;
    dk_color background_color;
    dk_node_mngr node_mngr;
    //dk_hitbox_mngr hitbox_mngr;
} dk_context;

dk_context *dk_init(int screen_width, int screen_height);
void dk_cleanup(dk_context *ctx);

#endif