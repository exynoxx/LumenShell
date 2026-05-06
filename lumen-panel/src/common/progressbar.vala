using DrawKit;

public class UiProgressBar : GLib.Object {

    private int value = 0;

    public int get_value() {
        return value;
    }

    public Color track_color = Color(){r=0.10f, g=0.11f, b=0.16f, a=1f};
    public Color fill_color = Color(){r=0.13f, g=0.76f, b=0.34f, a=1f};

    private int x = 0;
    private int y = 0;
    private int w = 0;
    private int h = 0;
    private float radius = 8f;

    public void set_bounds(int x, int y, int w, int h) {
        this.x = x;
        this.y = y;
        this.w = int.max(0, w);
        this.h = int.max(0, h);
        radius = int.min(this.h / 2, 12);
    }

    public void set_value(int v) {
        value = int.max(0, int.min(100, v));
    }

    public void render(Context ctx) {
        ctx.draw_rect_rounded(x, y, w, h, radius, track_color);

        int fill_w = (int) (w * value / 100.0f);
        if (fill_w > 0) {
            ctx.draw_rect_rounded(x, y, fill_w, h, radius, fill_color);
        }
    }
}
