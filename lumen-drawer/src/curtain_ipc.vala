namespace LumenDrawer {

    public class CurtainIpc : GLib.Object {

        // Only one reveal plugin is loaded; the other stop is a harmless no-op.
        public static bool close() {
            bool a = LumenCommon.WayfireIpc.send_method("wayfire-curtain-peek/stop");
            bool b = LumenCommon.WayfireIpc.send_method("wayfire-slide-peek/stop");
            return a || b;
        }
    }
}
