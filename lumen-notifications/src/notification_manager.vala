using GLib;

// Spec close reasons.
public const uint32 REASON_EXPIRED   = 1;
public const uint32 REASON_DISMISSED = 2;
public const uint32 REASON_CLOSED    = 3;
public const uint32 REASON_UNDEFINED = 4;

public class NotificationManager : Object {
    private uint32 next_id = 1;
    private HashTable<uint32, Notification> store
        = new HashTable<uint32, Notification>(direct_hash, direct_equal);

    public signal void notification_added(Notification n);
    public signal void notification_updated(Notification n);
    public signal void notification_closed(uint32 id, uint32 reason);

    /**
     * Submit a notification. If replaces_id matches an existing one, update
     * in place (and emit notification_updated). Otherwise assign a new id and
     * emit notification_added. Returns the id used.
     */
    public uint32 submit(uint32 replaces_id,
                         string app_name, string app_icon,
                         string summary, string body,
                         string[] actions,
                         Urgency urgency, string? image_path,
                         int expire_timeout) {
        Notification n;
        bool is_replace = false;
        if (replaces_id != 0 && store.contains(replaces_id)) {
            n = store.get(replaces_id);
            is_replace = true;
            cancel_expire(n);
        } else {
            n = new Notification(next_id++);
            store.insert(n.id, n);
        }
        n.app_name = app_name;
        n.app_icon = app_icon;
        n.summary = summary;
        n.body = body;
        n.actions = actions;
        n.urgency = urgency;
        n.image_path = image_path;
        n.expire_timeout = expire_timeout;

        if (is_replace) notification_updated(n);
        else            notification_added(n);

        arm_expire(n);
        return n.id;
    }

    public void close(uint32 id, uint32 reason) {
        if (!store.contains(id)) return;
        var n = store.get(id);
        cancel_expire(n);
        store.remove(id);
        notification_closed(id, reason);
    }

    public bool has(uint32 id) {
        return store.contains(id);
    }

    private void arm_expire(Notification n) {
        int ms;
        if (n.expire_timeout < 0)      ms = Theme.expire_default_ms;
        else if (n.expire_timeout == 0) return;   // never expires
        else                            ms = n.expire_timeout;

        uint32 id = n.id;
        n.expire_source = Timeout.add(ms, () => {
            if (store.contains(id)) {
                var nn = store.get(id);
                nn.expire_source = 0;
                close(id, REASON_EXPIRED);
            }
            return Source.REMOVE;
        });
    }

    private void cancel_expire(Notification n) {
        if (n.expire_source != 0) {
            Source.remove(n.expire_source);
            n.expire_source = 0;
        }
    }
}
