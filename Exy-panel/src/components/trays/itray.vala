using DrawKit;

public interface ITray : GLib.Object{
    public abstract int get_width();
    public abstract void set_position(int x, int y);
    //public abstract int get_max_width();
    /*  public abstract void expand();
    public abstract void contract();  */
    /*  
    public abstract void mouse_down();
    public abstract void mouse_up();
    public abstract void mouse_motion(int mouse_x, int mouse_y);  */
    public abstract void render(Context ctx);
}

public interface IClickable {
    public abstract void mouse_down();
    public abstract void mouse_up();
}

public interface IExpandable {
    public abstract int get_max_width();
    public abstract void expand();
    public abstract void contract();
}

public interface IUpdateable {
    public abstract void update();
    public abstract string get_status();
}

public interface IHoverable{
    public abstract void mouse_motion(int mouse_x, int mouse_y);

    public static bool is_hover(int x, int y, int width, int height, int mouse_x, int mouse_y){
        return (
            mouse_x >= x && 
            mouse_x <= x+width && 
            mouse_y >= y && 
            mouse_y <= y+height);
    }
}
