namespace LumenDrawer {

    public class CurtainIpc : GLib.Object {

        // Only one reveal plugin is loaded; the other stop is a harmless no-op.
        public static void close() {
            LumenCommon.WayfireIpc.send_method("wayfire-curtain-peek/stop");
            LumenCommon.WayfireIpc.send_method("wayfire-slide-peek/stop");
        }
    }
}
