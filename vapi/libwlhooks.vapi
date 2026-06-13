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

    [CCode(cname="get_output_scale", has_target = false)]
    public int get_output_scale();

    [CCode(cname="wlhooks_init")]
    public int init();

    // Toplevel-only init for clients that already own a wl_display (GTK).
    // Skips layer-shell, EGL, pointer/keyboard. Caller (GDK) drives dispatch.
    [CCode(cname="wlhooks_init_toplevel_with_display")]
    public int init_toplevel_with_display(Wl.Display display);

    [CCode(cname="wlhooks_destroy_toplevel")]
    public void destroy_toplevel();

    [CCode(cname="init_layer_shell")]
    public int init_layer_shell(string layer_name, int width, int height, Anchor anchor, bool exclusive_zone, int exclusive_zone_height = -1);

    [CCode(cname="layer_shell_destroy")]
    public void destroy_layer_shell();

    [CCode(cname="wlhooks_destroy")]
    public void destroy();

    [CCode(cname="display_dispatch_blocking")]
    public int display_dispatch_blocking();

    [CCode(cname="egl_swap_buffers")]
    public void swap_buffers();

    public delegate void ToplevelWindowNew(uint id, string app_id, string title);
    public delegate void ToplevelWindowRemove(uint id);
    public delegate void ToplevelWindowFocus(uint id);
    public delegate void ToplevelWindowOutput(uint id, string output_name, bool entered);

    [CCode(cname = "register_on_window_new")]
    public void register_on_window_new(ToplevelWindowNew cb);

    [CCode(cname = "register_on_window_rm")]
    public void register_on_window_rm(ToplevelWindowRemove cb);

    [CCode(cname = "register_on_window_focus")]
    public void register_on_window_focus(ToplevelWindowFocus cb);

    // Fires when a toplevel enters/leaves an output (per-monitor taskbar
    // filtering). output_name is the connector (matches Gdk.Monitor.connector).
    [CCode(cname = "register_on_window_output_changed")]
    public void register_on_window_output_changed(ToplevelWindowOutput cb);

    [CCode(cname = "toplevel_activate_by_id")]
    void toplevel_activate_by_id(uint id);

    [CCode(cname = "toplevel_minimize_by_id")]
    void toplevel_minimize_by_id(uint id);

    [CCode(cname = "toplevel_close_by_id")]
    void toplevel_close_by_id(uint id);

    // Report a window's taskbar-button rectangle, in `surface`'s coordinate
    // space, as the compositor's minimize-animation target (e.g. squeezimize).
    [CCode(cname = "toplevel_set_rectangle_by_id")]
    void toplevel_set_rectangle_by_id(uint id, Wl.Surface surface, int x, int y, int width, int height);

    public delegate void SeatMouseEnter();
    public delegate void SeatMouseLeave();
    public delegate void SeatMouseDown(uint32 button);
    public delegate void SeatMouseUp(uint32 button);
    public delegate void SeatMouseMotion(int x, int y);
    public delegate void SeatMouseScroll(int amount);
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

    [CCode(cname = "register_on_mouse_scroll")]
    void register_on_mouse_scroll(SeatMouseScroll cb);

    [CCode(cname = "register_on_key_down")]
    void register_on_key_down(SeatKeyDown? cb);

    [CCode(cname = "register_on_key_up")]
    void register_on_key_up(SeatKeyUp? cb);

    [CCode(cname = "set_grab_keyboard")]
    void grab_keyboard(bool value);
    [CCode(cname = "layer_shell_set_input_region")]
    void set_input_region(int x, int y, int w, int h);
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

    [CCode (cname = "activation_available")]
    public bool activation_available ();

    // Returns a freshly-allocated XDG activation token for `app_id` (may be ""),
    // or null if the compositor does not implement xdg_activation_v1.
    // The caller takes ownership.
    [CCode (cname = "activation_get_token")]
    public string? activation_get_token (string app_id);

    [CCode (cname = "activation_activate_self")]
    public void activation_activate_self ();

    // ---- wlr-output-management-v1 (display configuration) ------------------
    // In-process replacement for the wlr-randr CLI. Runs on a private event
    // queue (see protocols/output_management.c); roundtrips are synchronous and
    // do not reenter GDK dispatch.

    public delegate void OutputMgmtHead(int idx, string name, string description,
                                        bool enabled, int x, int y, int transform, double scale);
    public delegate void OutputMgmtMode(int head_idx, int width, int height,
                                        int refresh_mhz, bool preferred, bool current);

    [CCode (cname = "wlhooks_output_mgmt_init")]
    public int output_mgmt_init (Wl.Display display);

    [CCode (cname = "wlhooks_output_mgmt_destroy")]
    public void output_mgmt_destroy ();

    [CCode (cname = "wlhooks_output_mgmt_available")]
    public bool output_mgmt_available ();

    [CCode (cname = "wlhooks_output_mgmt_refresh")]
    public void output_mgmt_refresh ();

    [CCode (cname = "wlhooks_output_mgmt_for_each_head")]
    public void output_mgmt_for_each_head (OutputMgmtHead cb);

    [CCode (cname = "wlhooks_output_mgmt_for_each_mode")]
    public void output_mgmt_for_each_mode (int head_idx, OutputMgmtMode cb);

    [CCode (cname = "wlhooks_output_mgmt_config_begin")]
    public int output_mgmt_config_begin ();

    [CCode (cname = "wlhooks_output_mgmt_config_disable")]
    public void output_mgmt_config_disable (string name);

    [CCode (cname = "wlhooks_output_mgmt_config_enable")]
    public void output_mgmt_config_enable (string name, int w, int h, int refresh_mhz,
                                           int x, int y, int transform);

    [CCode (cname = "wlhooks_output_mgmt_config_apply")]
    public int output_mgmt_config_apply ();
}
