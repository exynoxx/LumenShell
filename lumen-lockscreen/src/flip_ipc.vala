// Wayfire IPC verb wrappers for the flip-to-lock transition.
//
// Sibling of converge_ipc.vala — same socket framing (lumen-common/wayfire_ipc.vala),
// same start/stop lifecycle, but drives the wayfire-flip-lock plugin instead:
// start(axis) rotates the live desktop edge-on about the Y or X axis before the
// lock surface maps; stop() resets the plugin underneath once the lock surface
// (which rotated back out of the edge-on frame) fully covers the screen.
//
// The axis is passed in the IPC data so lockscreen.json stays the single source
// of truth — the plugin obeys it rather than its own option, keeping the
// compositor-side flip and the GTK-side FlipReveal on the same axis.
//
// Silent no-op when _WAYFIRE_SOCKET is unset (self-test / not under Wayfire) or
// when the plugin isn't loaded — the lock still proceeds, just without the
// compositor-side flip.
public class FlipIpc : GLib.Object {

    // axis: "y" (rotate about the vertical axis) or "x" (horizontal axis).
    public static bool start(string axis) {
        var a = (axis == "x") ? "x" : "y";
        return LumenCommon.WayfireIpc.send_method_data(
            "wayfire-flip-lock/start", @"{\"axis\":\"$a\"}");
    }

    public static bool stop() {
        return LumenCommon.WayfireIpc.send_method("wayfire-flip-lock/stop");
    }
}
