using GLib;

/**
 * Pushes a sample notification through the D-Bus service so the visual stack
 * can be eyeballed without an external sender.
 */
public class NotifSelfTest : Object {

    private NotificationsService service;

    public NotifSelfTest(NotificationsService service) {
        this.service = service;
    }

    public void run() {
        stderr.printf("[lumen-notifications] --test: pushing a sample notification\n");
        Timeout.add(400, () => {
            string[] acts = { "ok", "OK", "later", "Later" };
            var hints = new HashTable<string, Variant>(str_hash, str_equal);
            try {
                service.notify_("lumen-notifications", 0, "dialog-information",
                                "Hello from lumen-notifications",
                                "This is a test banner. Click a button or the card.",
                                acts, hints, 8000);
            } catch (Error e) {
                stderr.printf("[lumen-notifications] --test failed: %s\n", e.message);
            }
            return Source.REMOVE;
        });
    }
}
