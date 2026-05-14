using Gtk;

public class NotifApp : Gtk.Application {

    private LayerWindow?         window  = null;
    private NotificationManager? manager = null;
    private NotificationsService? service = null;
    private DBusConnection?      conn    = null;
    private uint                 owner_id = 0;
    public  string               bus_name = "org.freedesktop.Notifications";
    public  string               bus_path = "/org/freedesktop/Notifications";
    public  bool                 test_mode = false;

    public NotifApp() {
        Object(
            application_id: "co.ibexa.LumenNotifications",
            flags: ApplicationFlags.NON_UNIQUE
        );
    }

    protected override void activate() {
        if (!GtkLayerShell.is_supported()) {
            stderr.printf("lumen-notifications: gtk4-layer-shell not supported\n");
            quit();
            return;
        }
        if (window != null) return;

        Theme.load();
        install_root_css();

        manager = new NotificationManager();
        window  = new LayerWindow(this);

        // Wire manager → window stack.
        manager.notification_added.connect((n) => {
            var b = window.stack.add_banner(n);
            wire_banner(b, n.id);
            window.set_visible(true);
        });
        manager.notification_updated.connect((n) => {
            var b = window.stack.get_banner(n.id);
            if (b != null) ((!) b).update_from(n);
        });
        manager.notification_closed.connect((id, reason) => {
            if (service != null) ((!) service).notification_closed(id, reason);
            window.stack.dismiss_banner(id);
        });
        window.stack.empty.connect(() => {
            window.set_visible(false);
        });
        window.clear_all_requested.connect(() => {
            window.stack.cascade_dismiss();
        });
        window.stack.close_requested.connect((id) => {
            if (manager != null && ((!) manager).has(id)) {
                ((!) manager).close(id, REASON_DISMISSED);
            }
        });

        service = new NotificationsService((!) manager);

        own_bus_name();
        hold();

        if (test_mode) run_self_test();
    }

    private void wire_banner(Banner b, uint32 id) {
        b.dismissed.connect(() => {
            if (manager != null && ((!) manager).has(id)) {
                ((!) manager).close(id, REASON_DISMISSED);
            }
        });
        b.action_invoked.connect((key) => {
            if (service != null) ((!) service).action_invoked(id, key);
            if (manager != null && ((!) manager).has(id)) {
                ((!) manager).close(id, REASON_DISMISSED);
            }
        });
    }

    private void install_root_css() {
        var provider = new Gtk.CssProvider();
        string css =
            ".lumen-notif-root { background-color: transparent; }" +
            ".lumen-notif-title { font-weight: bold; color: %s; }".printf(Theme.banner_text.to_string()) +
            ".lumen-notif-body  { color: %s; }".printf(Theme.banner_subtext.to_string()) +
            Theme.generate_action_css() +
            Theme.generate_clear_all_css();
        provider.load_from_string(css);
        Gtk.StyleContext.add_provider_for_display(
            (!) Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    private void own_bus_name() {
        owner_id = Bus.own_name(
            BusType.SESSION,
            bus_name,
            BusNameOwnerFlags.DO_NOT_QUEUE,
            (c) => {
                conn = c;
                try {
                    c.register_object(bus_path, (!) service);
                } catch (IOError e) {
                    stderr.printf("lumen-notifications: register_object failed: %s\n", e.message);
                }
            },
            () => {
                stderr.printf("lumen-notifications: acquired %s\n", bus_name);
            },
            () => {
                stderr.printf("lumen-notifications: could not acquire %s (already running?)\n",
                              bus_name);
                quit();
            }
        );
    }

    private void run_self_test() {
        stderr.printf("[lumen-notifications] --test: pushing a sample notification\n");
        Timeout.add(400, () => {
            string[] acts = { "ok", "OK", "later", "Later" };
            var hints = new HashTable<string, Variant>(str_hash, str_equal);
            try {
                ((!) service).notify_("lumen-notifications", 0, "dialog-information",
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

public static int main(string[] args) {
    var app = new NotifApp();
    string[] gtk_args = { args[0] };
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--test") {
            app.test_mode = true;
        } else if (args[i] == "--bus-name" && i + 1 < args.length) {
            app.bus_name = args[i + 1];
            i++;
        } else if (args[i] == "--bus-path" && i + 1 < args.length) {
            app.bus_path = args[i + 1];
            i++;
        } else {
            gtk_args += args[i];
        }
    }
    return app.run(gtk_args);
}
