// Fail-soft: without ext-idle-notify-v1, arm()/disarm() are no-ops.
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
