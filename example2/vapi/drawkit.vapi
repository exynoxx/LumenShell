[CCode (cheader_filename = "draw.h")]
namespace DrawKit {
    [CCode (cname = "dk_color", has_type_member = false)]
    public struct Color {
        public float r;
        public float g;
        public float b;
        public float a;
    }

    [CCode (cname = "dk_vec2", has_type_member = false)]
    public struct Vec2 {
        public float x;
        public float y;
    }

    [CCode (cname = "dk_context", has_type_member = false)]
    public struct Context {
        public GLES2.GLuint shader_program;
        public GLES2.GLuint rounded_rect_program;
        public GLES2.GLuint texture_program;
        public GLES2.GLuint vbo;
        public GLES2.GLuint vao;
        public int screen_width;
        public int screen_height;
        public Color background_color;
        public Color current_color;
    }

    [CCode (cname = "dk_init")]
    public bool init(ref Context ctx, int screen_width, int screen_height);

    [CCode (cname = "dk_cleanup")]
    public void cleanup(ref Context ctx);

    [CCode (cname = "dk_set_color")]
    public void set_color(ref Context ctx, float r, float g, float b, float a);

    [CCode (cname = "dk_set_bg_color")]
    public void set_bg_color(ref Context ctx, float r, float g, float b, float a);

    [CCode (cname = "dk_draw_rect")]
    public void draw_rect(ref Context ctx, float x, float y, float width, float height);

    [CCode (cname = "dk_draw_rounded_rect")]
    public void draw_rounded_rect(ref Context ctx, float x, float y, float width, float height, float radius);

    [CCode (cname = "dk_draw_texture")]
    public void draw_texture(ref Context ctx, GLES2.GLuint texture_id, float x, float y, float width, float height);

    [CCode (cname = "dk_begin_frame")]
    public void begin_frame(ref Context ctx);

    [CCode (cname = "dk_end_frame")]
    public void end_frame();
}

[CCode (cheader_filename = "texture.h")]
namespace DrawKit.Texture {
    [CCode (cname = "Image")]
    [SimpleType]
    public struct Image {
        public int width;
        public int height;
        public int channels;
        public unowned uint8[] data;
    }

    [CCode (cname = "dk_image_load")]
    public Image load_icon(string path);

    [CCode (cname = "dk_texture_upload")]
    public GLES2.GLuint upload(Image image);

    [CCode (cname = "dk_free_texture")]
    public void free_texture(GLES2.GLuint id);
}