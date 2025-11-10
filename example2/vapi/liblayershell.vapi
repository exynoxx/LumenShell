[CCode(cheader_filename="liblayershell.h")]
namespace LayerShell {

    [CCode(cname="Anchor", cprefix="", has_type_id=false)]
    public enum Anchor {
        UP = 1,
        DOWN = 2,
        LEFT = 4,
        RIGHT = 8,
        TOP = 13,
        BOTTOM = 14
    }

    // dk_mouse_info is a plain struct, returned as pointer
    [CCode(cname="dk_mouse_info", has_type_id=false)]
    public struct MouseInfo {
        public double mouse_x;
        public double mouse_y;
        public uint32 mouse_buttons;
    }

    // toplevel_info struct with pointer to next
    [CCode(cname="toplevel_info", has_type_id=false)]
    public struct ToplevelInfo {
        public string app_id;
        public string title;
        public uint32 state;
        public unowned ToplevelInfo* next;
        // handle omitted, add if needed: public unowned IntPtr handle;
    }

    [CCode(cname="init_layer_shell")]
    public int init(string layer_name, int width, int height, Anchor anchor, bool exclusive_zone);

    [CCode(cname="destroy_layer_shell")]
    public void destroy();

    [CCode(cname="display_dispatch_blocking")]
    public int display_dispatch_blocking();

    [CCode(cname="egl_swap_buffers")]
    public void swap_buffers();

    // Functions returning pointers to structs
    [CCode(cname="toplevel_get_list")]
    public unowned ToplevelInfo? toplevel_get_list();

    [CCode(cname="seat_mouse_info")]
    public unowned MouseInfo? seat_mouse_info();
}
