// Compiled only with PANEL_PEEK. A verb whose plugin isn't loaded is unregistered,
// so calling it is a harmless no-op.
#if PANEL_PEEK
public class PeekIpc : GLib.Object {

    // Whichever reveal plugin is loaded answers the generic lumen-peek verbs.
    public static void app_drawer () {
        LumenCommon.WayfireIpc.send_method("lumen-peek/toggle");
    }

    public static void push_start () {
        LumenCommon.WayfireIpc.send_method("wayfire-panel-push/start");
    }

    public static void push_stop () {
        LumenCommon.WayfireIpc.send_method("wayfire-panel-push/stop");
    }

    public static void night_light_toggle () {
        LumenCommon.WayfireIpc.send_method("wayfire-night-light/toggle");
    }
}
#endif
