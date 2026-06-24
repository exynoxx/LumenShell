using Gtk;

// Power actions, folded into the Control Center overview as a row of round
// buttons (no separate page). Keeps its tray icon in the compact bar; clicking
// it opens the overview where these live.
public class ExitTray : GLib.Object, ITrayApplet, IControlModule {

    LogindBridge bridge;
    TrayButton icon;
    Gtk.Box? row = null;

    public ExitTray (LogindBridge bridge) {
        this.bridge = bridge;
        icon = new TrayButton ("leaving");
    }

    public Gtk.Widget tray_widget () { return icon; }

    public string module_id () { return "exit"; }
    public Gtk.Widget? detail_view () { return null; }
    public Gtk.Widget home_tile () {
        if (row == null) row = build_row ();
        return row;
    }

    Gtk.Box build_row () {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            hexpand = true, homogeneous = true, margin_top = 2,
        };
        box.add_css_class ("cc-power-row");
        box.append (make_action ("lock",     "Lock",      () => lock_session ()));
        box.append (make_action ("suspend",  "Sleep",     () => bridge.suspend.begin ()));
        box.append (make_action ("logout",   "Log Out",   () => bridge.terminate_session.begin ()));
        box.append (make_action ("reboot",   "Restart",   () => bridge.reboot.begin ()));
        box.append (make_action ("shutdown", "Shut Down", () => bridge.power_off.begin ()));
        return box;
    }

    // Ask lumen-lockscreen to lock over DBus; no-op if the daemon isn't running.
    void lock_session () {
        Bus.get.begin (BusType.SESSION, null, (obj, res) => {
            try {
                var conn = Bus.get.end (res);
                conn.call.begin (
                    "org.lumenshell.Lock", "/org/lumenshell/Lock",
                    "org.lumenshell.Lock1", "Lock", null, null,
                    DBusCallFlags.NONE, 1000, null);
            } catch (Error e) {
                warning ("lumen-panel: lock request failed: %s", e.message);
            }
        });
    }

    delegate void ActionFunc ();

    Gtk.Widget make_action (string icon_name, string label_text, owned ActionFunc on_click) {
        var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) { halign = Gtk.Align.CENTER };

        var btn = new Gtk.Button () { halign = Gtk.Align.CENTER };
        btn.add_css_class ("cc-power-btn");
        var img = new Gtk.Image () { pixel_size = 22 };
        img.set_from_resource (CcStyle.icon (icon_name));
        btn.set_child (img);
        btn.clicked.connect (() => on_click ());
        col.append (btn);

        var lbl = new Gtk.Label (label_text) { halign = Gtk.Align.CENTER };
        lbl.add_css_class ("cc-power-label");
        col.append (lbl);

        return col;
    }
}
