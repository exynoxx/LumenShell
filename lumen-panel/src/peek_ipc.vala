// Wayfire IPC verb wrappers for the panel.
//
// Only compiled into the panel when the `with_panel_peek` meson option is on
// (it gates the PANEL_PEEK define). A standalone panel build omits this file
// entirely and never talks to Wayfire.
//
// The socket framing lives in lumen-common/wayfire_ipc.vala (shared with
// lumen-desktop); this file is just the panel's verbs.
#if PANEL_PEEK
public class PeekIpc : GLib.Object {

    public static bool toggle () {
        return LumenCommon.WayfireIpc.send_method("wayfire-desktop-peek/toggle");
    }

    // Toggle the app-drawer reveal (lumen-desktop). Only one of curtain-peek /
    // slide-peek is ever loaded, so the toggle for the inactive one is a
    // harmless no-op (its IPC method isn't registered) — same pattern as
    // lumen-desktop's CurtainIpc.close(). Used by the optional launcher button.
    public static bool app_drawer () {
        bool a = LumenCommon.WayfireIpc.send_method("wayfire-curtain-peek/toggle");
        bool b = LumenCommon.WayfireIpc.send_method("wayfire-slide-peek/toggle");
        return a || b;
    }

    // Push-reveal mode: slide the whole scene (wallpaper + windows) away from
    // the panel's edge so the panel can reveal into the freed strip. Harmless
    // no-op if wayfire-panel-push isn't loaded (verb unregistered).
    public static bool push_start () {
        return LumenCommon.WayfireIpc.send_method("wayfire-panel-push/start");
    }

    public static bool push_stop () {
        return LumenCommon.WayfireIpc.send_method("wayfire-panel-push/stop");
    }
}
#endif
