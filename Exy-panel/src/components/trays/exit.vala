
public class ExitTray : TrayIcon {

    public ExitTray() {
        base ("close");
    }

    public override void mouse_down(){
        if(base.hovered) 
            Process.spawn_command_line_async("pkill wayfire");
    }
    public override void mouse_up(){

    }
}