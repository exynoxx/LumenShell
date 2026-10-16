// An ON_DEMAND layer surface only sees keys after a click, so the global tray
// hotkey is a Wayfire [command] binding running:
//   dbus-send --session --dest=org.lumenshell.Panel /org/lumenshell/Panel \
//             org.lumenshell.Panel1.ToggleTray
[DBus (name = "org.lumenshell.Panel1")]
public class PanelService : GLib.Object {

    [DBus (visible = false)]
    public weak TrayBar tray { get; private set; }

    [DBus (visible = false)]
    public PanelService (TrayBar tray) {
        this.tray = tray;
    }

    public void toggle_tray () throws DBusError, IOError {
        if (tray != null) tray.toggle ();
    }

    [DBus (visible = false)]
    public void start () {
        Bus.own_name(
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
