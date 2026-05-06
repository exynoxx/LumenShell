using DrawKit;

public class UiHorizontalSlider : GLib.Object {

    public signal void value_changed(int value);

    public int min_value { get; set; default = 0; }
    public int max_value { get; set; default = 100; }
    private int value = 0;

    public int get_value() {
        return value;
    }

    public bool hovered { get; private set; default = false; }
    public bool dragging { get; private set; default = false; }

    public Color track_color = Color(){r=0.14f, g=0.15f, b=0.22f, a=1f};
    public Color fill_color = Color(){r=0.18f, g=0.62f, b=1.0f, a=1f};
    public Color knob_color = Color(){r=0.80f, g=0.84f, b=0.92f, a=1f};
    public Color knob_active_color = Color(){r=0.92f, g=0.95f, b=1f, a=1f};

    private int x = 0;
    private int y = 0;
    private int w = 0;
    private int h = 0;

    public void set_bounds(int x, int y, int w, int h) {
        this.x = x;
        this.y = y;
        this.w = int.max(0, w);
        this.h = int.max(0, h);
    }

    public void set_value(int new_value, bool emit_signal = false) {
        int clamped = int.max(min_value, int.min(max_value, new_value));
        if (clamped == value) return;
        value = clamped;
        if (emit_signal)
            value_changed(value);
    }

    public bool contains(int mx, int my) {
        return mx >= x && mx <= x + w
            && my >= y && my <= y + h;
    }

    public bool mouse_motion(int mx, int my) {
        bool old_hover = hovered;
        hovered = contains(mx, my);

        if (dragging) {
            update_from_pointer(mx);
            return true;
        }

        return old_hover != hovered;
    }

    public bool mouse_down(int mx, int my) {
        if (!contains(mx, my)) return false;
        dragging = true;
        hovered = true;
        update_from_pointer(mx);
        return true;
    }

    public bool mouse_up(int mx, int my) {
        bool was_dragging = dragging;
        dragging = false;
        hovered = contains(mx, my);
        return was_dragging;
    }

    public void render(Context ctx) {
        int track_y = y + h / 2 - 4;
        ctx.draw_rect_rounded(x, track_y, w, 8, 4f, track_color);

        int range = int.max(1, max_value - min_value);
        int fill_w = (int) ((w * (value - min_value)) / (float) range);
        if (fill_w > 0) {
            ctx.draw_rect_rounded(x, track_y, fill_w, 8, 4f, fill_color);
        }

        int knob_x = x + fill_w;
        knob_x = int.max(x + 6, int.min(x + w - 6, knob_x));
        Color kc = dragging || hovered ? knob_active_color : knob_color;
        ctx.draw_circle(knob_x, track_y + 4, 8, kc);
    }

    private void update_from_pointer(int mx) {
        if (w <= 0) return;

        int clamped = int.max(x, int.min(x + w, mx));
        float ratio = (clamped - x) / (float) w;
        int next_value = min_value + (int) ((max_value - min_value) * ratio);
        next_value = int.max(min_value, int.min(max_value, next_value));

        if (next_value != value) {
            value = next_value;
            value_changed(value);
        }
    }
}
