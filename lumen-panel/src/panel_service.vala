using GLib;

// Small session-bus control surface for the panel. Its sole job today is to let
// a global hotkey toggle the tray's Control Center without the pointer: the
// panel is a layer-shell surface with KeyboardMode.ON_DEMAND, so it only sees
// GTK key events AFTER it has been clicked — a true global toggle therefore has
// to come from outside the process. A Wayfire [command] keybinding calls
// ToggleTray over the session bus, e.g.
//
//   [command]
//   binding_tray = <super> KEY_A
//   command_tray = dbus-send --session --dest=org.lumenshell.Panel \
//                    /org/lumenshell/Panel org.lumenshell.Panel1.ToggleTray
//
// Naming mirrors the other LumenShell daemons (org.lumenshell.OSD/Lock): bus
// name org.lumenshell.Panel, object /org/lumenshell/Panel, interface
// org.lumenshell.Panel1. Only the tray-host panel owns the name; secondary
// monitors never run a service, so the verb always acts on the one real tray.
[DBus (name = "org.lumenshell.Panel1")]
public class PanelService : GLib.Object {

    // The primary tray (App.tray). Held only so ToggleTray can reach it; the
    // toggle itself fires expanded_changed, so the host PanelWindow grows or
    // shrinks its input region exactly as it does for a pointer click.
    [DBus (visible = false)]
    public weak TrayBar tray { get; private set; }

    uint owner_id = 0;

    [DBus (visible = false)]
    public PanelService (TrayBar tray) {
        this.tray = tray;
    }

    // Open the Control Center if collapsed, collapse it if open. Fire-and-forget
    // from the caller's side — there is nothing to return.
    public void toggle_tray () throws DBusError, IOError {
        if (tray != null) tray.toggle ();
    }

    // True while the Control Center is open. Lets a caller branch (e.g. a status
    // line) without a separate signal.
    public bool tray_expanded {
        get { return tray != null && tray.is_expanded (); }
    }

    [DBus (visible = false)]
    public void start () {
        owner_id = Bus.own_name(
            BusType.SESSION,
            "org.lumenshell.Panel",
            BusNameOwnerFlags.NONE,
            (conn) => {
                try {
                    conn.register_object("/org/lumenshell/Panel", this);
                } catch (IOError e) {
                    warning("lumen-panel: PanelService register_object failed: %s", e.message);
                }
            },
            null,
            () => {
                // Another panel instance already owns the name (e.g. a stray
                // process). Leave it alone rather than fighting for it.
                warning("lumen-panel: org.lumenshell.Panel already owned; ToggleTray disabled");
            });
    }
}
