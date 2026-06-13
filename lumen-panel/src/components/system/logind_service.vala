using GLib;

/**
 * LogindService — panel-owned, long-lived holder of the LogindBridge (same
 * shape as BatteryService / SoundService). It is the policy layer for
 * lock-on-suspend: when logind announces an imminent sleep it asks the
 * lockscreen to lock (a graceful no-op until lumen-lockscreen is installed),
 * then releases the delay inhibitor so the kernel can freeze.
 */
public class LogindService : GLib.Object {
    public LogindBridge bridge { get; private set; }

    const string LOCK_NAME  = "org.lumenshell.Lock";
    const string LOCK_PATH  = "/org/lumenshell/Lock";
    const string LOCK_IFACE = "org.lumenshell.Lock1";

    public LogindService() {
        bridge = new LogindBridge();
        bridge.prepare_for_sleep.connect(on_prepare_for_sleep);
        bridge.lock_requested.connect(() => request_lock());
    }

    void on_prepare_for_sleep(bool starting) {
        if (!starting) {
            // Resumed — re-arm the inhibitor for the next sleep.
            bridge.take_delay_inhibitor();
            return;
        }
        if (lock_on_suspend_enabled()) request_lock();
        // Always release so suspend is not stalled for the full delay window
        // (especially while the locker is absent and request_lock is a no-op).
        bridge.release_delay_inhibitor();
    }

    bool lock_on_suspend_enabled() {
        var p = Environment.get_user_config_dir() + "/lumen-shell/power.ini";
        var v = Ini.get_key_value(p, "lock-on-suspend");
        return v == null || v == "true";   // default on
    }

    // Ask lumen-lockscreen to lock. NameHasOwner-guarded: absent locker → no-op.
    void request_lock() {
        try {
            var conn = Bus.get_sync(BusType.SESSION, null);
            var r = conn.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "NameHasOwner",
                new Variant("(s)", LOCK_NAME), new VariantType("(b)"),
                DBusCallFlags.NONE, 800, null);
            bool owned = false;
            r.get("(b)", out owned);
            if (!owned) {
                debug("lock-on-suspend: %s not present; skipping", LOCK_NAME);
                return;
            }
            conn.call_sync(LOCK_NAME, LOCK_PATH, LOCK_IFACE, "Lock",
                           null, null, DBusCallFlags.NONE, 800, null);
        } catch (Error e) {
            warning("lock-on-suspend: %s", e.message);
        }
    }
}
