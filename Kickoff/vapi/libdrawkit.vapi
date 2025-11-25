using GLES2;

[CCode (cheader_filename = "structures.h,backend.h,texture.h,nanosvg.h", lower_case_cprefix = "dk_")]
namespace DrawKit {
    [CCode (cname = "dk_color", has_type_id = false)]
    [SimpleType]
    public struct Color {
        public float r;
        public float g;
        public float b;
        public float a;
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

        [CCode (cname = "dk_init")]
        public Context(int screen_width, int screen_height);

        // Backend functions
        /*  
        [CCode (cname = "dk_backend_init")]
        public bool backend_init();  */

        [CCode (cname = "dk_backend_cleanup")]
        public void backend_cleanup();

        [CCode (cname = "dk_set_bg_color")]
        public void set_bg_color(Color color);

        [CCode (cname = "dk_draw_rect")]
        public void draw_rect(int x, int y, int width, int height, Color color);

        [CCode (cname = "dk_draw_rect_rounded")]
        public void dk_draw_rect_rounded(int x, int y, int width, int height, float radius, Color color);

        [CCode (cname = "dk_draw_texture")]
        public void draw_texture(GLuint texture_id, int x, int y, int width, int height);

        [CCode (cname = "dk_begin_frame")]
        public void begin_frame();

        [CCode (cname = "dk_end_frame")]
        public void end_frame();

        // Layout functions
        [CCode (cname = "dk_reset")]
        public void reset();
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

    [CCode (cname = "rasterize_svg_to_rgba")]
    public Image *image_from_svg(string filename, int target_width, int target_height);
}