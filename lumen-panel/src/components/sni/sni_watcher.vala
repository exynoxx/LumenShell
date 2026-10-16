using GLib;
using Gee;

// Owns org.kde.StatusNotifierWatcher, or acts as a host for whoever already does
// (e.g. kded6). Apps hide their item until a host is registered; libappindicator
// re-registers when the Watcher name appears, so no enumeration is needed.
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
        // Per the de-facto protocol: a leading '/' means the app passed its
        // object path and the bus name is the message sender; otherwise the
        // string is the bus name and the path defaults to /StatusNotifierItem.
        if (service.has_prefix("/"))
            track((string) sender, service, service);
        else
            track(service, "/StatusNotifierItem", service);
    }

    void track (string bus, string path, string service) {
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

    // Hidden from the wire interface so they don't appear as bogus D-Bus signals.
    [DBus (visible = false)]
    public signal void item_added (string bus, string path, string key);
    [DBus (visible = false)]
    public signal void item_removed (string key);

    [DBus (visible = false)]
    public delegate void ItemVisitor (string bus, string path, string key);

    // Late-built SysTrays (secondary monitor, hotplug rebuild) miss item_added;
    // this replays the existing set.
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
                // Announce a host so libappindicator clients register.
                if (host_owner_id == 0) host_owner_id = Bus.own_name(
                    BusType.SESSION,
                    "org.kde.StatusNotifierHost-%d".printf((int) Posix.getpid()),
                    BusNameOwnerFlags.NONE, null, null, null);
                status_notifier_host_registered();
            },
            (conn) => {
                // Another watcher (e.g. KDE's kded6) owns the name. Don't fight
                // it: act as a host for it instead. We stay queued, so if it
                // exits the name_acquired path above takes over.
                if (conn != null) attach_foreign.begin(conn);
            });
    }

    async void attach_foreign (DBusConnection conn) {
        const string NAME  = "org.kde.StatusNotifierWatcher";
        const string PATH  = "/StatusNotifierWatcher";
        const string IFACE = "org.kde.StatusNotifierWatcher";

        if (foreign_subs.length == 0) {
            foreign_subs += conn.signal_subscribe(NAME, IFACE, "StatusNotifierItemRegistered",
                PATH, null, DBusSignalFlags.NONE, (c, s, p, i, sig, args) => {
                    track_foreign(args.get_child_value(0).get_string());
                });
            foreign_subs += conn.signal_subscribe(NAME, IFACE, "StatusNotifierItemUnregistered",
                PATH, null, DBusSignalFlags.NONE, (c, s, p, i, sig, args) => {
                    string bus, path;
                    split_foreign(args.get_child_value(0).get_string(), out bus, out path);
                    on_owner_vanished(bus + path);
                });
        }

        try {
            string host = "org.kde.StatusNotifierHost-%d".printf((int) Posix.getpid());
            if (host_owner_id == 0)
                host_owner_id = Bus.own_name(BusType.SESSION, host,
                                             BusNameOwnerFlags.NONE, null, null, null);
            yield conn.call(NAME, PATH, IFACE, "RegisterStatusNotifierHost",
                            new Variant("(s)", host), null, DBusCallFlags.NONE, -1, null);

            var reply = yield conn.call(NAME, PATH, "org.freedesktop.DBus.Properties", "Get",
                new Variant("(ss)", IFACE, "RegisteredStatusNotifierItems"),
                new VariantType("(v)"), DBusCallFlags.NONE, -1, null);
            foreach (var s in reply.get_child_value(0).get_variant().get_strv())
                track_foreign(s);
        } catch (Error e) {
            warning("lumen-panel systray: attaching to existing watcher failed: %s", e.message);
        }
    }

    uint[] foreign_subs = {};

    // Foreign watchers hand out "busname/object/path", or a bare bus name.
    static void split_foreign (string s, out string bus, out string path) {
        int slash = s.index_of_char('/');
        bus  = slash < 0 ? s : s.substring(0, slash);
        path = slash < 0 ? "/StatusNotifierItem" : s.substring(slash);
    }

    void track_foreign (string s) {
        string bus, path;
        split_foreign(s, out bus, out path);
        track(bus, path, s);
    }
}
