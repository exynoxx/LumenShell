namespace LumenCommon {
    public class DbusCli {
        // Any error reads as "not running".
        public static bool name_has_owner(GLib.DBusConnection conn, string name) {
            try {
                var reply = conn.call_sync(
                    "org.freedesktop.DBus",
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "NameHasOwner",
                    new GLib.Variant("(s)", name),
                    new GLib.VariantType("(b)"),
                    GLib.DBusCallFlags.NONE,
                    -1,
                    null);
                bool owned;
                reply.get("(b)", out owned);
                return owned;
            } catch (GLib.Error e) {
                return false;
            }
        }
    
        // Proxy to a running daemon for a short-lived CLI, or null after printing
        // why to stderr. Never auto-starts the daemon.
        public static T? connect<T>(string tool, string daemon, string name, string path) {
            DBusConnection conn;
            try {
                conn = Bus.get_sync(BusType.SESSION);
            } catch (Error e) {
                stderr.printf("%s: session bus unavailable: %s\n", tool, e.message);
                return null;
            }
            if (!name_has_owner(conn, name)) {
                stderr.printf("%s: %s daemon is not running\n", tool, daemon);
                return null;
            }
            try {
                T proxy = Bus.get_proxy_sync<T>(BusType.SESSION, name, path, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES | DBusProxyFlags.DO_NOT_AUTO_START);
                ((DBusProxy) proxy).set_default_timeout(1500);
                return proxy;
            } catch (Error e) {
                stderr.printf("%s: D-Bus proxy failed: %s\n", tool, e.message);
                return null;
            }
        }
    }
}
