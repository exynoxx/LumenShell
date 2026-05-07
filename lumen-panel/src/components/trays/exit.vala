using DrawKit;

public class ExitTray : IconAndText, IClickable {

    private const string EXIT_CMD = "pkill wayfire";

    public ExitTray() {
        base(new HoverableIcon("close"));
    }

    public void mouse_down(){
        if (base.icon.hovered)
            try {
                Process.spawn_command_line_async(EXIT_CMD);
            } catch (GLib.SpawnError e) {
                warning("Failed to spawn process: %s", e.message);
            }
    }

    public void mouse_up(){}
}
