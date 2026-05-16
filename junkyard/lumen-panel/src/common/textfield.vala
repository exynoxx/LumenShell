using DrawKit;
using Gee;

public class UiTextField : GLib.Object {

    private const uint32 KEY_CONTROL_L = 0xFFE3;
    private const uint32 KEY_CONTROL_R = 0xFFE4;
    private const uint32 KEY_BACKSPACE = 0xFF08;
    private const uint32 KEY_DELETE    = 0xFFFF;
    private const uint32 KEY_RETURN    = 0xFF0D;
    private const uint32 KEY_KP_ENTER  = 0xFF8D;
    private const uint32 KEY_ESCAPE    = 0xFF1B;

    private const uint32 KEYSYM_FUNCTION_RANGE_LOW  = 0xFD00;
    private const uint32 KEYSYM_FUNCTION_RANGE_HIGH = 0xFFFF;
    private const uint32 KEYSYM_ASCII_PRINTABLE_LOW  = 0x20;
    private const uint32 KEYSYM_ASCII_PRINTABLE_HIGH = 0x7E;
    private const uint32 KEYSYM_LATIN1_SUPP_LOW  = 0xA0;
    private const uint32 KEYSYM_LATIN1_SUPP_HIGH = 0xFF;
    private const uint32 KEYSYM_UNICODE_OFFSET = 0x01000000;
    private const uint32 KEYSYM_UNICODE_LOW  = 0x01000100;
    private const uint32 KEYSYM_UNICODE_HIGH = 0x0110FFFF;

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
    private HashSet<uint32> pressed_keys = new HashSet<uint32>();

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

    public void mouse_motion(int mx, int my) {
        bool old = hovered;
        hovered = contains(mx, my);
        if (old != hovered)
            redraw = true;
    }

    public void mouse_down(int mx, int my) {
        if (hovered) {
            focus();
        }
    }

    public void focus() {
        if (focused) return;
        focused = true;
        redraw = true;
        ctrl_down = false;
        pressed_keys.clear();
        WLHooks.register_on_key_down(on_key_down);
        WLHooks.register_on_key_up(on_key_up);
        focus_changed(true);
    }

    public void blur() {
        if (!focused) return;
        focused = false;
        ctrl_down = false;
        pressed_keys.clear();
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
            var sb = new StringBuilder();
            for (int i = 0; i < text.length; i++) sb.append("•");
            display = sb.str;
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

        // Dedupe key-down events: the compositor delivers a press *and* repeat
        // events for held keys via wl_keyboard.key. We don't implement repeat,
        // so ignore everything except the initial press transition.
        if (!pressed_keys.add(keysym)) return;

        if (keysym == KEY_CONTROL_L || keysym == KEY_CONTROL_R) {
            ctrl_down = true;
            return;
        }

        if (keysym == KEY_BACKSPACE) {
            if (ctrl_down) {
                set_text("", true);
            } else if (text.length > 0) {
                set_text(text.substring(0, text.length - 1), true);
            }
            return;
        }

        if (keysym == KEY_DELETE) {
            set_text("", true);
            return;
        }

        if (keysym == KEY_RETURN || keysym == KEY_KP_ENTER) {
            submitted();
            return;
        }

        if (keysym == KEY_ESCAPE) {
            cancelled();
            blur();
            return;
        }

        unichar c = keysym_to_unichar(keysym);
        if (c != 0) {
            set_text(text + c.to_string(), true);
        }
    }

    private void on_key_up(uint32 keysym) {
        pressed_keys.remove(keysym);
        if (keysym == KEY_CONTROL_L || keysym == KEY_CONTROL_R) {
            ctrl_down = false;
        }
    }

    private unichar keysym_to_unichar(uint32 keysym) {
        // X11 function/modifier/navigation keys live in 0xFD00–0xFFFF —
        // never printable. Without this guard, Shift/Tab/arrows/etc. would
        // each append a bogus codepoint to the field.
        if (keysym >= KEYSYM_FUNCTION_RANGE_LOW && keysym <= KEYSYM_FUNCTION_RANGE_HIGH) return 0;

        // Latin-1 (ASCII printable + Latin-1 supplement) maps 1:1.
        if ((keysym >= KEYSYM_ASCII_PRINTABLE_LOW && keysym <= KEYSYM_ASCII_PRINTABLE_HIGH)
            || (keysym >= KEYSYM_LATIN1_SUPP_LOW && keysym <= KEYSYM_LATIN1_SUPP_HIGH))
            return (unichar) keysym;

        // Unicode keysyms: 0x01000000 | codepoint.
        if (keysym >= KEYSYM_UNICODE_LOW && keysym <= KEYSYM_UNICODE_HIGH)
            return (unichar) (keysym - KEYSYM_UNICODE_OFFSET);

        return 0;
    }
}
