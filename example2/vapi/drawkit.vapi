using GLES2;

[CCode (cheader_filename = "structures.h,backend.h,layout.h,hover.h,texture.h", lower_case_cprefix = "dk_")]
namespace DrawKit {
    [CCode (cname = "dk_color", has_type_id = false)]
    [SimpleType]
    public struct Color {
        public float r;
        public float g;
        public float b;
        public float a;
    }

    [CCode (cname = "dk_float_mode", cprefix = "FLOAT_", has_type_id = false)]
    public enum FloatMode {
        LEFT,
        NONE
    }

    [CCode (cname = "dk_node_type", cprefix = "ELEMENT_", has_type_id = false)]
    public enum NodeType {
        BOX,
        RECT,
        TEXTURE
    }

    [CCode (cname = "dk_box_style", has_type_id = false)]
    public struct BoxStyle {
        public int padding_top;
        public int padding_right;
        public int padding_bottom;
        public int padding_left;
        public int gap;
        public FloatMode float_mode;
    }

    [CCode (cname = "struct dk_ui_node", has_type_id = false)]
    public struct UINode {
        public NodeType type;
        public float width;
        public float height;
        public float x;
        public float y;

        //onion translation
        [CCode (cname = "data.style")]
        public BoxStyle style;
        
        [CCode (cname = "data.texture_id")]
        public uint texture_id;
        
        [CCode (cname = "data.color")]
        public Color color;

        public bool hovered;
        public UINode* parent;
        public UINode* first_child;
        public UINode* last_child;
        public UINode* next_sibling;
    }

    [CCode (cname = "dk_node_mngr", has_type_id = false)]
    public struct NodeManager {
        public UINode* nodes;
        public int element_count;
        public UINode* root;
        public UINode* current_parent;
    }

    [CCode (cname = "dk_context", free_function = "dk_cleanup", has_type_id = false)]
    [Compact]
    public class Context {
        public GLuint shader_program;
        public GLuint rounded_rect_program;
        public GLuint texture_program;
        public GLuint vbo;
        public GLuint vao;
        public int screen_width;
        public int screen_height;
        public Color background_color;
        public NodeManager node_mngr;

        [CCode (cname = "dk_init")]
        public Context(int screen_width, int screen_height);

        // Backend functions
        [CCode (cname = "dk_backend_init")]
        public bool backend_init();

        [CCode (cname = "dk_backend_cleanup")]
        public void backend_cleanup();

        [CCode (cname = "dk_set_bg_color")]
        public void set_bg_color(Color color);

        [CCode (cname = "dk_draw_node")]
        public void draw_node(UINode* node);

        [CCode (cname = "dk_draw_rect")]
        public void draw_rect(int x, int y, int width, int height, Color color);

        [CCode (cname = "dk_draw_texture")]
        public void draw_texture(GLuint texture_id, int x, int y, int width, int height);

        [CCode (cname = "dk_begin_frame")]
        public void begin_frame();

        [CCode (cname = "dk_end_frame")]
        public void end_frame();

        // Layout functions
        [CCode (cname = "dk_reset")]
        public void reset();

        [CCode (cname = "dk_start_box")]
        public void start_box(int width, int height);

        [CCode (cname = "dk_box_set_padding")]
        public void box_set_padding(int top, int right, int bottom, int left);

        [CCode (cname = "dk_box_set_gap")]
        public void box_set_gap(int gap);

        [CCode (cname = "dk_box_float")]
        public void box_float(FloatMode float_mode);

        [CCode (cname = "dk_end_box")]
        public void end_box();

        [CCode (cname = "dk_rect")]
        public unowned UINode* rect(int width, int height, Color color);

        [CCode (cname = "dk_texture")]
        public unowned UINode* texture(GLuint texture_id, int width, int height);

        [CCode (cname = "evaluate_positions")]
        public static void evaluate_positions(UINode* elem, float parent_x, float parent_y);

        [CCode (cname = "dk_draw")]
        public void draw(int root_x, int root_y);

        // Hover/hitbox functions
        [CCode (cname = "dk_hitbox_query")]
        public int hitbox_query(int px, int py);
    }

    // Texture functions
    [CCode (cname = "Image", destroy_function = "", has_type_id = false)]
    [SimpleType]
    public struct Image {
        public int width;
        public int height;
        public int channels;
        public uint8[] data;
    }

    [CCode (cname = "dk_image_load")]
    public Image image_load(string path);

    [CCode (cname = "dk_texture_upload")]
    public GLuint texture_upload(Image image);

    [CCode (cname = "dk_texture_free")]
    public void texture_free(GLuint id);
}