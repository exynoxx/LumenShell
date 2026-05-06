using DrawKit;

public class UiButton : GLib.Object {

    public signal void clicked();

    public string label { get; set; default = ""; }
    public bool enabled { get; set; default = true; }
    public bool hovered { get; private set; default = false; }

    public Color normal_color = Color(){r=0.14f, g=0.21f, b=0.40f, a=1f};
    public Color hover_color = Color(){r=0.20f, g=0.30f, b=0.56f, a=1f};
    public Color pressed_color = Color(){r=0.11f, g=0.17f, b=0.32f, a=1f};
    public Color text_color = Color(){r=1f, g=1f, b=1f, a=1f};

    public int x = 0;
    public int y = 0;
    public int w = 0;
    public int h = 0;
    public float radius = 8f;
    public float text_size = 12f;

    private bool pressed = false;

    public void set_bounds(int x, int y, int w, int h) {
        this.x = x;
        this.y = y;
        this.w = int.max(0, w);
        this.h = int.max(0, h);
    }

    public bool contains(int mx, int my) {
        return mx >= x && mx <= x + w
            && my >= y && my <= y + h;
    }

    public void mouse_motion(int mx, int my) {
        bool old = hovered;
        hovered = contains(mx, my);
        if (old != hovered)
            redraw = true;
    }

    public void mouse_down(int mx, int my) {
        if (!enabled) return;
        if (!contains(mx, my)) return;

        pressed = true;
    }

    public void mouse_up(int mx, int my) {
        if (!enabled) return;
        if (pressed && hovered) {
            clicked();
            pressed = false;
            redraw = true;
        }
    }

    public void cancel_press() {
        pressed = false;
    }

    public void render(Context ctx) {
        Color c = normal_color;
        if (!enabled) {
            c = Color(){
                r=normal_color.r,
                g=normal_color.g,
                b=normal_color.b,
                a=normal_color.a * 0.45f
            };
        } else if (pressed) {
            c = pressed_color;
        } else if (hovered) {
            c = hover_color;
        }

        ctx.draw_rect_rounded(x, y, w, h, radius, c);
        pdt_center(ctx, label, x + w / 2, y + (h - (int) text_size) / 2, text_size, text_color);
    }
}
