using Gtk;

public class NotifApp : Gtk.Application {

    private LayerWindow          window;
    private NotificationManager  manager;
    private NotificationsService service;
    private DBusConnection?      conn = null;
    private uint                 owner_id = 0;
    private bool                 activated = false;
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
        if (activated) return;
        activated = true;

        Theme.load();
        install_root_css();

        manager = new NotificationManager();
        window  = new LayerWindow(this);
        service = new NotificationsService(manager);

        wire_signals();
        own_bus_name();
        hold();

        if (test_mode) new NotifSelfTest(service).run();
    }

    private void wire_signals() {
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
            service.notification_closed(id, reason);
            window.stack.dismiss_banner(id);
        });
        window.stack.empty.connect(() => {
            window.set_visible(false);
        });
        window.clear_all_requested.connect(() => {
            window.stack.cascade_dismiss();
        });
        window.stack.close_requested.connect((id) => {
            if (manager.has(id)) manager.close(id, REASON_DISMISSED);
        });
    }

    private void wire_banner(Banner b, uint32 id) {
        b.dismissed.connect(() => {
            if (manager.has(id)) manager.close(id, REASON_DISMISSED);
        });
        b.action_invoked.connect((key) => {
            service.action_invoked(id, key);
            if (manager.has(id)) manager.close(id, REASON_DISMISSED);
        });
    }

    private void install_root_css() {
        var provider = new Gtk.CssProvider();
        provider.load_from_string(Theme.generate_root_css());
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
                    c.register_object(bus_path, service);
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
