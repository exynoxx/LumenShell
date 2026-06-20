// Shared DBus CLI helpers (lumen-common). Source-level reuse only.
namespace LumenCommon {
    public class DbusCli {
        // True if `name` currently has an owner on the given bus connection.
        // Returns false on any error (treat as "not running").
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
    }
}
