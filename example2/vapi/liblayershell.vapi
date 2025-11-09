[CCode (cheader_filename = "liblayershell.h")]
namespace LayerShell {
    [CCode (cname = "Anchor", cprefix = "", has_type_id = false)]
    public enum Anchor {
        UP = 1,
        DOWN = 2,
        LEFT = 4,
        RIGHT = 8,
        TOP = 13,
        BOTTOM = 14
    }

    [CCode (cname = "dk_mouse_info", destroy_function = "", has_type_id = false)]
    [SimpleType]
    public struct MouseInfo {
        public double mouse_x;
        public double mouse_y;
        public uint32 mouse_buttons;
    }

    [CCode (cname = "struct toplevel_info", destroy_function = "", has_type_id = false)]
    public struct ToplevelInfo {
        public string app_id;
        public string title;
        public uint32 state;
        public ToplevelInfo* next;
    }

    [CCode (cname = "init_layer_shell")]
    public int init(string layer_name, int width, int height, Anchor anchor, bool exclusive_zone);

    [CCode (cname = "destroy_layer_shell")]
    public void destroy();

    [CCode (cname = "display_dispatch_blocking")]
    public int display_dispatch_blocking();

    [CCode (cname = "egl_swap_buffers")]
    public void swap_buffers();

    [CCode (cname = "toplevel_get_list")]
    public unowned ToplevelInfo? toplevel_get_list();

    [CCode (cname = "seat_mouse_info")]
    public unowned MouseInfo? seat_mouse_info();
}