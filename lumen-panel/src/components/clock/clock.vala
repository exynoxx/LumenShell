using DrawKit;

public class Clock : Object, ITray {

    private const int FONT_SIZE = 16;

    private int x;
    private int y;
    private int width;
    private int margin_top;
    private int margin_left;

    private string text;

    public Clock(Context ctx) {
        refresh_text();
        width       = ctx.width_of(text, FONT_SIZE);
        margin_top  = (Tray.TRAY_HEIGHT - ctx.height_of(text, FONT_SIZE)) / 2;
        margin_left = width / 2;  // text drawn with x in centre

        GLib.Timeout.add_seconds(1, () => {
            refresh_text();
            redraw = true;
            return Source.CONTINUE;
        });
    }

    public int get_width() { return width; }

    public void set_position(int x, int y) {
        this.x = x + margin_left;
        this.y = y + margin_top + 5;
    }

    public void mouse_down() {}
    public void mouse_up() {}
    public void mouse_motion(int mouse_x, int mouse_y) {}

    public void render(Context ctx) {
        ctx.draw_text(text, x, y, FONT_SIZE, {1, 1, 1, 1});
    }

    private void refresh_text() {
        text = new DateTime.now_local().format("%Y-%m-%d  %H:%M:%S");
    }
}
