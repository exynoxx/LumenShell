using DrawKit;

public class ExitTray : IconAndText,  IClickable {

    public ExitTray(Context ctx) {
        base (ctx, new HoverableIcon("close"), "close");
    }

    public void mouse_down(){
        if(base.icon.hovered)
            try {
                Process.spawn_command_line_async("pkill wayfire");
            } catch (GLib.SpawnError e) {
                warning("Failed to spawn process: %s", e.message);
            }
    }
    public void mouse_up(){}

}