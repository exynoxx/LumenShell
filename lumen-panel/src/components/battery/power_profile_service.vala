using GLib;

/**
 * PowerProfileService — single power-profile state path for the battery page.
 *
 * Detects the backend (power-profiles-daemon, else TLP) and its supported
 * profiles once at construction, then re-queries the active profile every 10 s
 * (same cadence as BatteryService). state_changed fires whenever the active
 * profile changes. backend == NONE means the page hides the selector.
 */
public class PowerProfileService : GLib.Object {

    private const uint POLL_SEC = 10;

    public signal void state_changed();

    public PowerBackend  backend   { get; private set; default = PowerBackend.NONE; }
    public PowerProfile[] available = {};
    public PowerProfile  current   { get; private set; default = PowerProfile.UNKNOWN; }

    private PowerProfileClient client = new PowerProfileClient();

    public PowerProfileService() {
        backend   = client.detect_backend();
        available = client.available(backend);
        current   = client.current(backend);

        if (backend != PowerBackend.NONE) {
            GLib.Timeout.add_seconds(POLL_SEC, () => {
                requery();
                return Source.CONTINUE;
            });
        }
    }

    /**
     * Apply a profile. Optimistic: reflect the choice immediately so the
     * selector doesn't bounce back while the (async) command runs, then
     * reconcile once with a delayed re-query.
     */
    public void select(PowerProfile p) {
        if (backend == PowerBackend.NONE || p == PowerProfile.UNKNOWN) return;
        if (p != current) {
            current = p;
            state_changed();
        }
        client.set(backend, p);
        GLib.Timeout.add(800, () => {
            requery();
            return Source.REMOVE;
        });
    }

    private void requery() {
        var latest = client.current(backend);
        // UNKNOWN means "couldn't read" — keep the last known value rather than
        // clearing the highlight on a transient read failure.
        if (latest != PowerProfile.UNKNOWN && latest != current) {
            current = latest;
            state_changed();
        }
    }
}
