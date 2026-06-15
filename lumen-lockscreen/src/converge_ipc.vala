// Wayfire IPC verb wrappers for lumen-lockscreen.
//
// The socket framing lives in lumen-common/wayfire_ipc.vala (shared with the
// panel/desktop peek wrappers — see that module for the frame format and the
// _WAYFIRE_SOCKET env var). The lockscreen drives the wayfire-converge-lock
// plugin: start() collapses the live desktop to the centre seam before the lock
// surface maps; stop() resets the plugin underneath once the lock surface (which
// expanded back out of the seam) fully covers the screen.
//
// Silent no-op when _WAYFIRE_SOCKET is unset (self-test / not under Wayfire) or
// when the plugin isn't loaded — the lock still proceeds, just without the
// compositor-side collapse.
public class ConvergeIpc : GLib.Object {

    public static bool start() {
        return LumenCommon.WayfireIpc.send_method("wayfire-converge-lock/start");
    }

    public static bool stop() {
        return LumenCommon.WayfireIpc.send_method("wayfire-converge-lock/stop");
    }
}
