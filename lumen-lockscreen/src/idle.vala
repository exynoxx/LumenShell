using GLib;

// IdleWatcher — self-lock on inactivity via ext-idle-notify-v1, bound through
// wlhooks on GTK's wl_display (same pattern as the panel's ToplevelStore). No
// external idle daemon required. Fail-soft: if the compositor lacks the
// protocol, `available` stays false and arm()/disarm() are no-ops, so the other
// lock triggers still work.
public class IdleWatcher : GLib.Object {

    public signal void idled();

    private bool   available = false;
    private uint32 timeout_ms;

    public IdleWatcher(uint32 timeout_ms) {
        this.timeout_ms = timeout_ms;

        var gdk = Gdk.Display.get_default();
        if (!(gdk is Gdk.Wayland.Display)) {
            warning("lumen-lockscreen: not on Wayland; idle auto-lock disabled");
            return;
        }
        unowned Wl.Display wl = ((Gdk.Wayland.Display) gdk).get_wl_display();
        if (WLHooks.idle_notify_init(wl) != 0) {
            warning("lumen-lockscreen: compositor lacks ext-idle-notify-v1; "
                    + "idle auto-lock disabled");
            return;
        }
        available = true;
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
