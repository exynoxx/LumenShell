// Compiled only with PANEL_PEEK. A verb whose plugin isn't loaded is unregistered,
// so calling it is a harmless no-op.
#if PANEL_PEEK
public class PeekIpc : GLib.Object {

    // Only one of curtain-peek / slide-peek is loaded; the other toggle no-ops.
    public static bool app_drawer () {
        bool a = LumenCommon.WayfireIpc.send_method("wayfire-curtain-peek/toggle");
        bool b = LumenCommon.WayfireIpc.send_method("wayfire-slide-peek/toggle");
        return a || b;
    }

    public static bool push_start () {
        return LumenCommon.WayfireIpc.send_method("wayfire-panel-push/start");
    }

    public static bool push_stop () {
        return LumenCommon.WayfireIpc.send_method("wayfire-panel-push/stop");
    }

    public static bool night_light_toggle () {
        return LumenCommon.WayfireIpc.send_method("wayfire-night-light/toggle");
    }
}
#endif
