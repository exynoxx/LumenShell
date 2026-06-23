using GLib;
using Gee;

// StatusNotifierWatcher + Host implementation.
//
// The modern Linux tray (Discord, Telegram, Steam, …) is the StatusNotifier
// protocol: D-Bus based, display-server agnostic. Three roles exist:
//   - Watcher: the well-known registry at org.kde.StatusNotifierWatcher that
//     apps call to announce their tray item. WE own this name.
//   - Host:    the thing that actually draws icons (our panel). Apps refuse to
//     register (or stay hidden) unless a host is registered, so we own a
//     org.kde.StatusNotifierHost-<pid> name and flag IsStatusNotifierHostRegistered.
//   - Item:    one per app; rendered by SniItem.
//
// If nothing owns the Watcher name, SNI apps run trayless — which is exactly
// why Discord's icon was invisible before this existed. Apps using
// libappindicator watch for the Watcher name to appear and (re)register, so we
// don't need to enumerate pre-existing items: owning the name triggers them.
[DBus (name = "org.kde.StatusNotifierWatcher")]
public class SniWatcher : GLib.Object {

    class ItemRec {
        public string bus;
        public string path;
        public string service;   // the original string the app registered with
        public uint   watch_id;
        public ItemRec (string bus, string path, string service) {
            this.bus = bus; this.path = path; this.service = service;
        }
    }

    HashMap<string, ItemRec> items = new HashMap<string, ItemRec>();
    uint watcher_owner_id = 0;
    uint host_owner_id = 0;
    bool owns_name = false;

    public signal void status_notifier_item_registered (string service);
    public signal void status_notifier_item_unregistered (string service);
    public signal void status_notifier_host_registered ();
    public signal void status_notifier_host_unregistered ();

    public bool is_status_notifier_host_registered { get; private set; default = true; }
    public int  protocol_version { get { return 0; } }

    public string[] registered_status_notifier_items {
        owned get {
            var keys = new string[items.size];
            int i = 0;
            foreach (var rec in items.values) keys[i++] = rec.bus + rec.path;
            return keys;
        }
    }

    public void register_status_notifier_item (string service, GLib.BusName sender)
            throws DBusError, IOError {
        string bus, path;
        // Per the de-facto protocol: a leading '/' means the app passed its
        // object path and the bus name is the message sender; otherwise the
        // string is the bus name and the path defaults to /StatusNotifierItem.
        if (service.has_prefix("/")) {
            bus  = (string) sender;
            path = service;
        } else {
            bus  = service;
            path = "/StatusNotifierItem";
        }

        string key = bus + path;
        if (items.has_key(key)) return;

        var rec = new ItemRec(bus, path, service);
        // Drop the item when its owning connection disappears (apps don't always
        // call UnregisterStatusNotifierItem before quitting).
        rec.watch_id = Bus.watch_name(
            BusType.SESSION, bus, BusNameWatcherFlags.NONE,
            null,
            (conn, name) => on_owner_vanished(key));
        items[key] = rec;

        item_added(bus, path, key);
        status_notifier_item_registered(service);
    }

    public void register_status_notifier_host (string service)
            throws DBusError, IOError {
        // We are our own host; the name is already flagged registered. Still
        // emit the signal so late-registering items get the nudge.
        status_notifier_host_registered();
    }

    // Hidden from the wire interface so they don't appear as bogus D-Bus
    // signals.
    [DBus (visible = false)]
    public signal void item_added (string bus, string path, string key);
    [DBus (visible = false)]
    public signal void item_removed (string key);

    [DBus (visible = false)]
    public delegate void ItemVisitor (string bus, string path, string key);

    // Replay the currently-registered items to a freshly-attached observer.
    // A SysTray widget built on a secondary monitor (or rebuilt after a
    // hotplug) connects after items have already registered, so it can't rely
    // on item_added alone — this hands it the existing set.
    [DBus (visible = false)]
    public void foreach_item (ItemVisitor visit) {
        foreach (var rec in items.values) visit(rec.bus, rec.path, rec.bus + rec.path);
    }

    void on_owner_vanished (string key) {
        var rec = items[key];
        if (rec == null) return;
        items.unset(key);
        if (rec.watch_id != 0) Bus.unwatch_name(rec.watch_id);
        item_removed(key);
        status_notifier_item_unregistered(rec.service);
    }

    [DBus (visible = false)]
    public void start () {
        watcher_owner_id = Bus.own_name(
            BusType.SESSION,
            "org.kde.StatusNotifierWatcher",
            BusNameOwnerFlags.NONE,
            (conn) => {
                try {
                    conn.register_object("/StatusNotifierWatcher", this);
                } catch (IOError e) {
                    warning("lumen-panel systray: register_object failed: %s", e.message);
                }
            },
            () => {
                owns_name = true;
                // Announce a host so libappindicator clients register.
                host_owner_id = Bus.own_name(
                    BusType.SESSION,
                    "org.kde.StatusNotifierHost-%d".printf((int) Posix.getpid()),
                    BusNameOwnerFlags.NONE, null, null, null);
                status_notifier_host_registered();
            },
            () => {
                // Another watcher (a full DE) already owns the name. Leave the
                // tray empty rather than fighting over it.
                warning("lumen-panel systray: org.kde.StatusNotifierWatcher already owned; tray disabled");
            });
    }
}
