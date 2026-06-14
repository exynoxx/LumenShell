// Wayfire IPC verb wrappers for lumen-desktop.
//
// The socket framing lives in lumen-common/wayfire_ipc.vala (shared with the
// panel's peek_ipc.vala — see that module for the frame format and the
// _WAYFIRE_SOCKET env var). lumen-desktop only ever needs to *close* the
// reveal (hide itself again) — it is revealed by the compositor-side binding,
// which also hands it keyboard focus. The single close() call on launch makes
// sure a restart doesn't leave the grid stranded visible if a peek was open.

namespace LumenDesktop {

    public class CurtainIpc : GLib.Object {

        // Close whichever reveal is active (hide the desktop grid). Only one of
        // the two reveal plugins is ever loaded at a time, so the stop for the
        // inactive one is a harmless no-op (its IPC method isn't registered);
        // either way the desktop grid ends up hidden again. No-op too when the
        // active reveal is already idle on the compositor side.
        public static bool close() {
            bool a = LumenCommon.WayfireIpc.send_method("wayfire-curtain-peek/stop");
            bool b = LumenCommon.WayfireIpc.send_method("wayfire-slide-peek/stop");
            return a || b;
        }
    }
}
