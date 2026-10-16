using GLib;

// Battery state from UPower's composite DisplayDevice on the system bus; UPower
// handles BAT0/BAT1/HID discovery and charge_* vs energy_* units.
public class BatteryService : GLib.Object {

    const string BUS       = "org.freedesktop.UPower";
    const string ROOT_PATH = "/org/freedesktop/UPower";
    const string DEV_PATH  = "/org/freedesktop/UPower/devices/DisplayDevice";
    const string DEV_IFACE = "org.freedesktop.UPower.Device";

    // Safety net for a UPower build that never emits PropertiesChanged.
    const uint RESYNC_SEC = 30;

    public signal void state_changed ();

    // "charging" / "discharging" / "full" / "" (unknown, incl. no battery).
    public string raw_status = "";
    public int    percent    = 0;
    public bool   ac_online  = false;

    DBusProxy? device = null;
    DBusProxy? root   = null;

    public BatteryService () {
        device = make_proxy (DEV_PATH, DEV_IFACE);
        root   = make_proxy (ROOT_PATH, BUS);
        if (device == null || root == null) {
            warning ("lumen-panel battery: UPower unavailable, battery state will not update");
            return;
        }

        device.g_properties_changed.connect (() => refresh.begin ());
        root.g_properties_changed.connect (() => refresh.begin ());
        GLib.Timeout.add_seconds (RESYNC_SEC, () => {
            refresh.begin ();
            return Source.CONTINUE;
        });
        refresh.begin ();
    }

    // The icon ladder, shared by the tray button and the Control Center tile.
    public string icon_name () {
        if (ac_online)                return "wired";
        if (raw_status == "charging") return "charging";
        if (raw_status == "discharging" || raw_status.contains ("full"))
            return percent >= 70 ? "high" : percent >= 30 ? "mid" : "low";
        return "nobattery";
    }

    async void refresh () {
        var dev = yield get_all (device, DEV_IFACE);
        var up  = yield get_all (root, BUS);
        if (dev == null || up == null) return;

        string status = state_name (lookup_uint (dev, "State"));
        int    pct     = int.min (100, int.max (0, (int) Math.round (lookup_double (dev, "Percentage"))));
        bool   on_ac   = !lookup_bool (up, "OnBattery");

        if (status == raw_status && pct == percent && on_ac == ac_online) return;

        raw_status = status;
        percent    = pct;
        ac_online  = on_ac;
        state_changed ();
    }

    // UpDeviceState. PENDING_CHARGE/PENDING_DISCHARGE mean "plugged but idle" /
    // "on battery but idle", so they fold into the charging/discharging cases;
    // EMPTY is a discharged battery, not a missing one.
    static string state_name (uint32 state) {
        switch (state) {
            case 1: case 5:          return "charging";
            case 2: case 3: case 6:  return "discharging";
            case 4:                  return "full";
            default:                 return "";
        }
    }

    DBusProxy? make_proxy (string path, string iface) {
        try {
            return new DBusProxy.for_bus_sync (
                BusType.SYSTEM, DBusProxyFlags.NONE, null, BUS, path, iface, null);
        } catch (Error e) {
            return null;
        }
    }

    async VariantDict? get_all (DBusProxy p, string iface) {
        try {
            var reply = yield p.call ("org.freedesktop.DBus.Properties.GetAll",
                                      new Variant ("(s)", iface),
                                      DBusCallFlags.NONE, 2000, null);
            return new VariantDict (reply.get_child_value (0));
        } catch (Error e) {
            return null;
        }
    }

    static double lookup_double (VariantDict d, string key) {
        var v = d.lookup_value (key, VariantType.DOUBLE);
        return (v != null) ? v.get_double () : 0.0;
    }

    static uint32 lookup_uint (VariantDict d, string key) {
        var v = d.lookup_value (key, VariantType.UINT32);
        return (v != null) ? v.get_uint32 () : 0;
    }

    static bool lookup_bool (VariantDict d, string key) {
        var v = d.lookup_value (key, VariantType.BOOLEAN);
        return (v != null) && v.get_boolean ();
    }
}
