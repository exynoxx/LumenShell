using DrawKit;

public class TrayClock : ITray{
    
    private int x;
    private int y;

    private string text;
    private const int FONT_SIZE = 12;

    private int width;

    public TrayClock(Context ctx){
        width = ctx.width_of(text, FONT_SIZE);
    }

    public int get_width() {
        return width;
    }

    public void set_position(int x, int y){
        this.x = x;
        this.y = y;
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