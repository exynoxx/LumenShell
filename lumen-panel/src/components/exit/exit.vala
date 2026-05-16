using Gtk;

// Right-most tray button — terminates the compositor session.
public class ExitTray : TrayButton {
    const string EXIT_CMD = "pkill wayfire";

    public ExitTray () {
        base("close");
        clicked.connect(() => {
            try { Process.spawn_command_line_async(EXIT_CMD); }
            catch (SpawnError e) { warning("Exit spawn failed: %s", e.message); }
        });
    }
}
