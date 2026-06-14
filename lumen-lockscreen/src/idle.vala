using GLib;

// IdleWatcher — self-lock on inactivity via ext-idle-notify-v1. The wlhooks
// binding is set up once by LockManager (WLHooks.idle_notify_init); this just
// arms/disarms the notification. Fail-soft:
// if the compositor lacks the protocol, `available` stays false and arm()/
// disarm() are no-ops, so the other lock triggers still work.
public class IdleWatcher : GLib.Object {

    public signal void idled();

    private bool   available;
    private uint32 timeout_ms;

    public IdleWatcher(uint32 timeout_ms) {
        this.timeout_ms = timeout_ms;
        this.available = WLHooks.idle_notify_available();
        if (!available)
            warning("lumen-lockscreen: ext-idle-notify-v1 unavailable; "
                    + "idle auto-lock disabled");
    }

    // Arm the idle notification. timeout 0 disables idle auto-lock entirely.
    public void arm() {
        if (!available || timeout_ms == 0) return;
        WLHooks.idle_notify_register(timeout_ms, () => idled(), () => {});
    }

    // Disarm — used while already locked so the idle event does not re-fire.
    public void disarm() {
        if (!available) return;
        WLHooks.idle_notify_unregister();
    }
}
