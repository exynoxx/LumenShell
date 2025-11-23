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
        public float mouse_x;
        public float mouse_y;
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

    public delegate void ToplevelWindowNew(string app_id, string title);
    public delegate void ToplevelWindowRemove(string app_id, string title);
    public delegate void ToplevelWindowFocus(string app_id, string title);

    [CCode(cname = "register_on_window_new")]
    public void register_on_window_new(ToplevelWindowNew cb);

    [CCode(cname = "register_on_window_rm")]
    public void register_on_window_rm(ToplevelWindowRemove cb);

    [CCode(cname = "register_on_window_focus")]
    public void register_on_window_focus(ToplevelWindowFocus cb);

    [CCode(cname = "toplevel_activate_by_id")]
    void toplevel_activate_by_id(string app_id, string title);

    [CCode(cname = "toplevel_minimize_by_id")]
    void toplevel_minimize_by_id(string app_id, string title);

    [CCode(cname="seat_mouse_info")]
    public unowned MouseInfo *seat_mouse_info();

    public delegate void SeatMouseEnter();
    public delegate void SeatMouseLeave();
    public delegate void SeatMouseDown();
    public delegate void SeatMouseUp();
    public delegate void SeatMouseMotion(double x, double y);

    [CCode(cname = "register_on_mouse_enter")]
    void register_on_mouse_enter(SeatMouseEnter cb);

    [CCode(cname = "register_on_mouse_leave")]
    void register_on_mouse_leave(SeatMouseLeave cb);

    [CCode(cname = "register_on_mouse_down")]
    void register_on_mouse_down(SeatMouseDown cb);

    [CCode(cname = "register_on_mouse_up")]
    void register_on_mouse_up(SeatMouseUp cb);

    [CCode(cname = "register_on_mouse_motion")]
    void register_on_mouse_motion(SeatMouseMotion cb);
}
