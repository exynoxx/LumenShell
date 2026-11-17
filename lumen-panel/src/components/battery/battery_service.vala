// Battery state from UPower's composite DisplayDevice on the system bus; UPower
// handles BAT0/BAT1/HID discovery and charge_* vs energy_* units.
public class BatteryService : GLib.Object {

    const string BUS       = "org.freedesktop.UPower";
    const string ROOT_PATH = "/org/freedesktop/UPower";
    const string DEV_PATH  = "/org/freedesktop/UPower/devices/DisplayDevice";
    const string DEV_IFACE = "org.freedesktop.UPower.Device";

    public signal void state_changed ();
    public signal void ac_changed ();

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

        // NONE flags: the sync constructor loads, and GLib keeps updating, the
        // property cache, so reads are local.
        device.g_properties_changed.connect (refresh);
        root.g_properties_changed.connect (refresh);
        refresh ();
    }

    // The icon ladder, shared by the tray button and the Control Center tile.
    public string icon_name () {
        if (ac_online)                return "wired";
        if (raw_status == "charging") return "charging";
        if (raw_status == "discharging" || raw_status.contains ("full"))
            return percent >= 70 ? "high" : percent > 30 ? "mid" : "low";
        return "nobattery";
    }

    void refresh () {
        var st  = cached (device, "State", VariantType.UINT32);
        var pv  = cached (device, "Percentage", VariantType.DOUBLE);
        var onb = cached (root, "OnBattery", VariantType.BOOLEAN);
        // No owner (UPower not running) leaves the cache empty: keep the last state.
        if (st == null && pv == null && onb == null) return;

        string status = state_name (st != null ? st.get_uint32 () : 0);
        int    pct     = ((int) Math.round (pv != null ? pv.get_double () : 0.0)).clamp (0, 100);
        bool   on_ac   = !(onb != null && onb.get_boolean ());

        if (status == raw_status && pct == percent && on_ac == ac_online) return;

        bool ac_flip = on_ac != ac_online;
        raw_status = status;
        percent    = pct;
        ac_online  = on_ac;
        state_changed ();
        if (ac_flip) ac_changed ();
    }

    static Variant? cached (DBusProxy p, string key, VariantType type) {
        var v = p.get_cached_property (key);
        return (v != null && v.is_of_type (type)) ? v : null;
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
}
