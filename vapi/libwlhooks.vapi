[CCode(cheader_filename="wlhooks.h")]
namespace WLHooks {

    // ---- foreign-toplevel (lumen-panel, lumen-drawer) ----------------------
    // Toplevel-only init for clients that already own a wl_display (GTK).
    // Caller (GDK) drives dispatch.
    [CCode(cname="wlhooks_init_toplevel_with_display")]
    public int init_toplevel_with_display(Wl.Display display);

    [CCode(cname="wlhooks_destroy_toplevel")]
    public void destroy_toplevel();

    public delegate void ToplevelWindowNew(uint id, string app_id, string title);
    public delegate void ToplevelWindowRemove(uint id);
    public delegate void ToplevelWindowFocus(uint id);
    public delegate void ToplevelWindowOutput(uint id, string output_name, bool entered);

    [CCode (cname = "register_on_window_new")]
    public void register_on_window_new(ToplevelWindowNew cb);

    [CCode (cname = "register_on_window_rm")]
    public void register_on_window_rm(ToplevelWindowRemove cb);

    [CCode (cname = "register_on_window_focus")]
    public void register_on_window_focus(ToplevelWindowFocus cb);

    // Fires when a toplevel enters/leaves an output (per-monitor taskbar
    // filtering). output_name is the connector (matches Gdk.Monitor.connector).
    [CCode (cname = "register_on_window_output_changed")]
    public void register_on_window_output_changed(ToplevelWindowOutput cb);

    [CCode (cname = "toplevel_activate_by_id")]
    void toplevel_activate_by_id(uint id);

    [CCode (cname = "toplevel_minimize_by_id")]
    void toplevel_minimize_by_id(uint id);

    [CCode (cname = "toplevel_close_by_id")]
    void toplevel_close_by_id(uint id);

    // Report a window's taskbar-button rectangle, in `surface`'s coordinate
    // space, as the compositor's minimize-animation target (e.g. squeezimize).
    [CCode (cname = "toplevel_set_rectangle_by_id")]
    void toplevel_set_rectangle_by_id(uint id, Wl.Surface surface, int x, int y, int width, int height);

    // ---- wlr-output-management-v1 (display configuration) ------------------
    // In-process replacement for the wlr-randr CLI. Runs on a private event
    // queue (see protocols/output_management.c); roundtrips are synchronous and
    // do not reenter GDK dispatch.

    public delegate void OutputMgmtHead(int idx, string name, string description,
                                        bool enabled, int x, int y, int transform, double scale);
    public delegate void OutputMgmtMode(int head_idx, int width, int height,
                                        int refresh_mhz, bool preferred, bool current);
    public delegate void OutputMgmtHeadId(int idx, string name, string make, string model,
                                          string serial, string description);
    // Fired on hotplug, only when the connected SET of heads changes.
    public delegate void OutputMgmtOutputsChanged();

    [CCode (cname = "wlhooks_output_mgmt_init")]
    public int output_mgmt_init (Wl.Display display);

    // Headless-daemon hotplug + main-loop integration (lumen-session).
    [CCode (cname = "wlhooks_output_mgmt_register_outputs_changed")]
    public void output_mgmt_register_outputs_changed (OutputMgmtOutputsChanged cb);

    [CCode (cname = "wlhooks_output_mgmt_get_fd")]
    public int output_mgmt_get_fd ();

    [CCode (cname = "wlhooks_output_mgmt_dispatch")]
    public int output_mgmt_dispatch ();

    [CCode (cname = "wlhooks_output_mgmt_destroy")]
    public void output_mgmt_destroy ();

    [CCode (cname = "wlhooks_output_mgmt_available")]
    public bool output_mgmt_available ();

    [CCode (cname = "wlhooks_output_mgmt_refresh")]
    public void output_mgmt_refresh ();

    [CCode (cname = "wlhooks_output_mgmt_for_each_head")]
    public void output_mgmt_for_each_head (OutputMgmtHead cb);

    [CCode (cname = "wlhooks_output_mgmt_for_each_head_identity")]
    public void output_mgmt_for_each_head_identity (OutputMgmtHeadId cb);

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

    // ---- ext-idle-notify-v1 (lumen-lockscreen idle auto-lock) --------------
    // Binds wl_seat + ext_idle_notifier_v1 on GTK's wl_display; the GDK main
    // loop dispatches the idled/resumed callbacks. Init BEFORE arming.

    public delegate void IdleNotifyCallback ();

    // Returns 0 if the notifier was bound, -1 if the compositor lacks
    // ext-idle-notify-v1 (caller should fall back / skip idle lock).
    [CCode (cname = "wlhooks_idle_notify_init")]
    public int idle_notify_init (Wl.Display display);

    [CCode (cname = "wlhooks_idle_notify_available")]
    public bool idle_notify_available ();

    // Arm a single notification: `idled` after timeout_ms of seat inactivity,
    // `resumed` on the next input. Replaces any previously-armed one.
    [CCode (cname = "wlhooks_idle_notify_register")]
    public int idle_notify_register (uint32 timeout_ms,
                                     IdleNotifyCallback idled,
                                     IdleNotifyCallback resumed);

    // Disarm (e.g. while already locked, so it does not re-fire).
    [CCode (cname = "wlhooks_idle_notify_unregister")]
    public void idle_notify_unregister ();

    [CCode (cname = "wlhooks_idle_notify_destroy")]
    public void idle_notify_destroy ();

    // ---- zwp-idle-inhibit-v1 (lumen-panel Caffeine) ------------------------
    // Returns 0 if the inhibit manager was bound, -1 if unsupported.
    [CCode (cname = "wlhooks_idle_inhibit_init")]
    public int idle_inhibit_init (Wl.Display display);

    // Create (on) / destroy (off) the single idle inhibitor on `surface`.
    [CCode (cname = "wlhooks_idle_inhibit_set")]
    public int idle_inhibit_set (Wl.Surface surface, bool on);
}
