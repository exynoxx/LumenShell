using Gtk;

public class ExitPage : Gtk.Box {

    const int PAD = 14;

    LogindBridge bridge;

    public ExitPage (LogindBridge bridge) {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.bridge = bridge;
        add_css_class("exit-page");
        set_size_request(440, 320);

        var title = new Gtk.Label("Session") {
            xalign = 0,
            margin_start = PAD,
            margin_top = PAD,
            margin_bottom = 6,
        };
        title.add_css_class("page-title");
        append(title);

        var rows = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            hexpand = true,
            vexpand = true,
            margin_bottom = PAD,
        };

        var row1 = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 24) {
            halign = Gtk.Align.CENTER,
        };
        row1.append(make_action("lock",      "Lock",      () => lock_session()));
        row1.append(make_action("suspend",   "Suspend",   () => bridge.suspend.begin()));
        row1.append(make_action("hibernate", "Hibernate", () => bridge.hibernate.begin()));
        rows.append(row1);

        var row2 = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 24) {
            halign = Gtk.Align.CENTER,
        };
        row2.append(make_action("logout",    "Log Out",   () => bridge.terminate_session.begin()));
        row2.append(make_action("reboot",    "Reboot",    () => bridge.reboot.begin()));
        row2.append(make_action("shutdown",  "Shutdown",  () => bridge.power_off.begin()));
        rows.append(row2);

        append(rows);
    }

    // Ask lumen-lockscreen to lock, over DBus (org.lumenshell.Lock1). Decoupled
    // from the binary: works whenever the daemon is running, no-op otherwise.
    // Fire-and-forget so the click never blocks the panel.
    void lock_session () {
        Bus.get.begin(BusType.SESSION, null, (obj, res) => {
            try {
                var conn = Bus.get.end(res);
                conn.call.begin(
                    "org.lumenshell.Lock", "/org/lumenshell/Lock",
                    "org.lumenshell.Lock1", "Lock", null, null,
                    DBusCallFlags.NONE, 1000, null);
            } catch (Error e) {
                warning("lumen-panel: lock request failed: %s", e.message);
            }
        });
    }

    delegate void ActionFunc ();

    Gtk.Widget make_action (string icon_name, string label_text, owned ActionFunc on_click) {
        var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 8) {
            halign = Gtk.Align.CENTER,
        };

        var btn = new Gtk.Button() {
            halign = Gtk.Align.CENTER,
        };
        btn.add_css_class("exit-action");
        var img = new Gtk.Image() {
            pixel_size = 28,
        };
        img.set_from_resource("/dev/lumen/panel/icons/" + icon_name + ".svg");
        btn.set_child(img);
        btn.clicked.connect(() => on_click());
        col.append(btn);

        var lbl = new Gtk.Label(label_text) {
            halign = Gtk.Align.CENTER,
        };
        lbl.add_css_class("exit-action-label");
        col.append(lbl);

        return col;
    }
}
