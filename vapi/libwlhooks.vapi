[CCode(cheader_filename="wlhooks.h")]
namespace WLHooks {

    [CCode(cname="Anchor", cprefix="", has_type_id=false)]
    public enum Anchor {
        UP = 1,
        DOWN = 2,
        LEFT = 4,
        RIGHT = 8,
        TOP = 13,
        BOTTOM = 14
    }

    [CCode(cname="surface_size_t", has_type_id=false)]
    public struct SurfaceSize {
        public int width;
        public int height;
    }

    [CCode(cname="get_screen_size", has_target = false)]
    public unowned SurfaceSize *get_screen_size();

    // toplevel_info struct with pointer to next
    [CCode(cname="toplevel_info", has_type_id=false)]
    public struct ToplevelInfo {
        public uint32 id;
        public string app_id;
        public string title;
        public uint32 state;
        public unowned ToplevelInfo* next;
        // handle omitted, add if needed: public unowned IntPtr handle;
    }

    [CCode(cname="wlhooks_init")]
    public int init();

    [CCode(cname="init_layer_shell")]
    public int init_layer_shell(string layer_name, int width, int height, Anchor anchor, bool exclusive_zone);

    [CCode(cname="layer_shell_destroy")]
    public int destroy_layer_shell();

    [CCode(cname="wlhooks_destroy")]
    public void destroy();

    [CCode(cname="display_dispatch_blocking")]
    public int display_dispatch_blocking();

    [CCode(cname="egl_swap_buffers")]
    public void swap_buffers();

    public delegate void ToplevelWindowNew(uint id, string app_id, string title);
    public delegate void ToplevelWindowRemove(uint id);
    public delegate void ToplevelWindowFocus(uint id);

    [CCode(cname = "register_on_window_new")]
    public void register_on_window_new(ToplevelWindowNew cb);

    [CCode(cname = "register_on_window_rm")]
    public void register_on_window_rm(ToplevelWindowRemove cb);

    [CCode(cname = "register_on_window_focus")]
    public void register_on_window_focus(ToplevelWindowFocus cb);

    [CCode(cname = "toplevel_activate_by_id")]
    void toplevel_activate_by_id(uint id);

    [CCode(cname = "toplevel_minimize_by_id")]
    void toplevel_minimize_by_id(uint id);

    public delegate void SeatMouseEnter();
    public delegate void SeatMouseLeave();
    public delegate void SeatMouseDown();
    public delegate void SeatMouseUp();
    public delegate void SeatMouseMotion(int x, int y);
    public delegate void SeatKeyDown(uint32 key);
    public delegate void SeatKeyUp(uint32 key);

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

    [CCode(cname = "register_on_key_down")]
    void register_on_key_down(SeatKeyDown cb);

    [CCode(cname = "register_on_key_up")]
    void register_on_key_up(SeatKeyUp cb);

    [CCode(cname = "set_grab_keyboard")]
    void grab_keyboard(bool value);

    [CCode (cname = "screencopy_buffer_t", destroy_function = "screencopy_buffer_free", has_type_id = false)]
    [Compact]
    public class Buffer {
        public uint32 width;
        public uint32 height;
        public uint32 stride;
        public uint32 format;
        [CCode (array_length = false)]
        public uint8[] data;
    }

    [CCode (cname = "screencopy_ready_callback")]
    public delegate void ReadyCallback (Buffer buffer);

    [CCode (cname = "screencopy_failed_callback")]
    public delegate void FailedCallback ();

    [CCode (cname = "screencopy_capture")]
    public void capture (ReadyCallback ready_cb, FailedCallback failed_cb);
}
