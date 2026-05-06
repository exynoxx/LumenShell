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

/**
 * Implemented by tray icons that own an expansion page.
 * The Tray class uses this to map icon hovers to page indices.
 */
public interface IHasPage : GLib.Object {
    /** Return the page this icon opens. */
    public abstract ITrayPage get_page();
    /** Return true when this icon's hover circle is currently hovered. */
    public abstract bool is_icon_hovered();
    /** Set icon visual active state while page is open. */
    public abstract void set_page_active(bool active);
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
