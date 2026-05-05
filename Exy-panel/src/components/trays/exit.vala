using DrawKit;

public class ExitTray : IconAndText,  IClickable {

    public ExitTray(Context ctx) {
        base (ctx, new HoverableIcon("close"), "close");
    }

    public void mouse_down(){
        if(base.icon.hovered) 
            Process.spawn_command_line_async("pkill wayfire");
    }
    public void mouse_up(){}

}