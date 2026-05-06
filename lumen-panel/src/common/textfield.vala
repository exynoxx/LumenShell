using DrawKit;

public class UiTextField : GLib.Object {

    public signal void changed(string text);
    public signal void submitted();
    public signal void cancelled();
    public signal void focus_changed(bool focused);

    private string text = "";

    public string get_text() {
        return text;
    }
    public string placeholder { get; set; default = ""; }

    public bool focused { get; private set; default = false; }
    public bool hovered { get; private set; default = false; }
    public bool obscure_text { get; set; default = false; }

    public float text_size = 13f;

    public Color bg_color = Color(){r=0.10f, g=0.11f, b=0.16f, a=1f};
    public Color hover_bg_color = Color(){r=0.12f, g=0.13f, b=0.19f, a=1f};
    public Color focus_bg_color = Color(){r=0.14f, g=0.16f, b=0.24f, a=1f};
    public Color focus_glow_color = Color(){r=0.22f, g=0.48f, b=1.0f, a=0.55f};
    public Color text_color = Color(){r=1f, g=1f, b=1f, a=0.92f};
    public Color placeholder_color = Color(){r=0.42f, g=0.43f, b=0.50f, a=0.85f};
    public Color cursor_color = Color(){r=0.50f, g=0.65f, b=1.0f, a=0.9f};

    private int x = 0;
    private int y = 0;
    private int w = 0;
    private int h = 0;
    private bool ctrl_down = false;

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

    public void set_text(string value, bool emit_signal = false) {
        text = value;
        if (emit_signal)
            changed(text);
    }

    public bool mouse_motion(int mx, int my) {
        bool old = hovered;
        hovered = contains(mx, my);
        return old != hovered;
    }

    public bool mouse_down(int mx, int my) {
        if (contains(mx, my)) {
            focus();
            return true;
        }

        if (focused)
            blur();
        return false;
    }

    public void focus() {
        if (focused) return;
        focused = true;
        ctrl_down = false;
        WLHooks.register_on_key_down(on_key_down);
        WLHooks.register_on_key_up(on_key_up);
        focus_changed(true);
    }

    public void blur() {
        if (!focused) return;
        focused = false;
        ctrl_down = false;
        WLHooks.register_on_key_down(null);
        WLHooks.register_on_key_up(null);
        focus_changed(false);
    }

    public void render(Context ctx) {
        Color bg = focused ? focus_bg_color : (hovered ? hover_bg_color : bg_color);

        if (focused) {
            ctx.draw_rect_rounded(x - 1, y - 1, w + 2, h + 2, 9f, focus_glow_color);
        }
        ctx.draw_rect_rounded(x, y, w, h, 8f, bg);

        string display = text;
        if (obscure_text && text != "") {
            display = "";
            for (int i = 0; i < text.length; i++)
                display += "•";
        }

        string shown = display != "" ? display : placeholder;
        Color col = display != "" ? text_color : placeholder_color;
        pdt(ctx, shown, x + 10, y + (h - (int) text_size) / 2, text_size, col);

        if (focused) {
            int cursor_x = x + 10 + ctx.width_of(display, text_size);
            ctx.draw_rect(cursor_x, y + 7, 2, h - 14, cursor_color);
        }
    }

    private void on_key_down(uint32 keysym) {
        if (!focused) return;

        if (keysym == 0xFFE3 || keysym == 0xFFE4) {
            ctrl_down = true;
            return;
        }

        if (keysym == 0xFF08) {
            if (ctrl_down) {
                set_text("", true);
            } else if (text.length > 0) {
                set_text(text.substring(0, text.length - 1), true);
            }
            return;
        }

        if (keysym == 0xFFFF) {
            set_text("", true);
            return;
        }

        if (keysym == 0xFF0D || keysym == 0xFF8D) {
            submitted();
            return;
        }

        if (keysym == 0xFF1B) {
            cancelled();
            blur();
            return;
        }

        if (is_printable_keysym(keysym)) {
            set_text(text + ((unichar) keysym).to_string(), true);
        }
    }

    private void on_key_up(uint32 keysym) {
        if (keysym == 0xFFE3 || keysym == 0xFFE4) {
            ctrl_down = false;
        }
    }

    private bool is_printable_keysym(uint32 keysym) {
        return (keysym >= 0x20 && keysym <= 0x7E)
            || (keysym >= 0xA0 && keysym <= 0x10FFFF);
    }
}
