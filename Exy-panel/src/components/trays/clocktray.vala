using DrawKit;

public class ClockTray : Object, ITray {
    
    private int x;
    private int y;

    private string text;
    private const int FONT_SIZE = 16;

    private int width;
    private int margin_top;
    private int margin_left;

    public ClockTray(Context ctx){
        update();
        width = ctx.width_of(text, FONT_SIZE);
        margin_top = (Tray.TRAY_HEIGHT - ctx.height_of(text, FONT_SIZE))/2;
        margin_left = width/2; //text drawn with x in center
    }

    public int get_width() {
        return width;
    }

    public void set_position(int x, int y){
        this.x = x+margin_left;
        this.y = y+margin_top+5;
    }

    public void mouse_down(){}
    public void mouse_up(){}
    public void mouse_motion(int mouse_x, int mouse_y) {}

    private void update() {
        var now = new DateTime.now_local();
        text = now.format("%Y-%m-%d %H:%M:%S");
    }

    public void render(Context ctx){
        if(Utils.elapsed_ms() >= 5000)
            update();

        ctx.draw_text(text, x, y, FONT_SIZE, {1,1,1,1});
    }
}