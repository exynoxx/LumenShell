public class PowerProfileService : GLib.Object {

    public signal void state_changed();

    public PowerBackend  backend   { get; private set; default = PowerBackend.NONE; }
    public PowerProfile[] available = {};
    public PowerProfile  current   { get; private set; default = PowerProfile.UNKNOWN; }

    private PowerProfileClient client = new PowerProfileClient();
    private bool requery_in_flight = false;

    public PowerProfileService() {
        backend   = client.detect_backend();
        available = client.available(backend);
        requery();

        if (backend == PowerBackend.PPD)
            client.changed.connect(requery);
    }

    // TLP has no change signal; main.vala calls this when AC state flips (TLP's
    // profile follows AC). PPD is event-driven off its PropertiesChanged.
    public void refresh() {
        if (backend == PowerBackend.TLP) requery();
    }

    // Optimistic: show the choice immediately so the selector doesn't bounce back,
    // then reconcile with a delayed re-query.
    public void select(PowerProfile p) {
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

    // TLP's read spawns `tlp-stat -s`, so it runs off the main thread; PPD reads
    // GDBusProxy's property cache and stays inline.
    private void requery() {
        if (backend != PowerBackend.TLP) {
            apply(client.current(backend));
            return;
        }
        if (requery_in_flight) return;
        requery_in_flight = true;
        new GLib.Thread<void>("power-profile-poll", () => {
            var latest = client.current(backend);
            GLib.Idle.add(() => {
                requery_in_flight = false;
                apply(latest);
                return Source.REMOVE;
            });
        });
    }

    private void apply(PowerProfile latest) {
        // UNKNOWN means "couldn't read" — keep the last known value rather than
        // clearing the highlight on a transient read failure.
        if (latest != PowerProfile.UNKNOWN && latest != current) {
            current = latest;
            state_changed();
        }
    }
}
