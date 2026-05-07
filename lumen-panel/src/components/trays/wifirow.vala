using DrawKit;

/**
 * WifiRow — composite that renders one network entry in the WiFi list.
 *
 * WifiPage sets ssid/signal/security/is_connected/hovered/selected
 * each frame then calls render().  The embedded disconnect button
 * handles its own hover/press state and emits disconnect_clicked.
 */
public class WifiRow : GLib.Object {

    public signal void disconnect_clicked();

    public bool selected     = false;
    public bool hovered      = false;
    public bool is_connected = false;
    public string ssid       = "";
    public int    signal_val = 0;
    public string security   = "";

    private UiSignalBars signal_bars    = new UiSignalBars();
    private UiButton     disconnect_btn = new UiButton();

    private Color sel_bg_col;
    private Color hov_bg_col;
    private Color conn_name_col;
    private Color norm_name_col;
    private Color lock_col;

    private int rx;
    private int ry;
    private int rw;
    private int rh;

    private const int PAD = 14;

    public WifiRow() {
        sel_bg_col    = Color(){r=0.10f, g=0.24f, b=0.62f, a=0.88f};
        hov_bg_col    = Color(){r=0.17f, g=0.18f, b=0.24f, a=0.85f};
        conn_name_col = Color(){r=0.18f, g=0.88f, b=0.42f, a=1f};
        norm_name_col = Color(){r=0.90f, g=0.91f, b=0.94f, a=1f};
        lock_col      = Color(){r=0.52f, g=0.52f, b=0.58f, a=1f};

        disconnect_btn.label         = "×";
        disconnect_btn.text_size     = 13f;
        disconnect_btn.radius        = 6f;
        disconnect_btn.normal_color  = Color(){r=0.74f, g=0.20f, b=0.20f, a=0.96f};
        disconnect_btn.hover_color   = Color(){r=0.90f, g=0.30f, b=0.30f, a=1f};
        disconnect_btn.pressed_color = Color(){r=0.66f, g=0.16f, b=0.16f, a=1f};
        disconnect_btn.clicked.connect(() => disconnect_clicked());
    }

    public void set_bounds(int x, int y, int w, int h) {
        rx = x;  ry = y;  rw = w;  rh = h;
    }

    public bool contains(int mx, int my) {
        return mx >= rx && mx <= rx + rw && my >= ry && my <= ry + rh;
    }

    public void mouse_motion(int mx, int my) {
        if (is_connected) disconnect_btn.mouse_motion(mx, my);
    }

    public void mouse_down(int mx, int my) {
        if (is_connected) disconnect_btn.mouse_down(mx, my);
    }

    public void mouse_up(int mx, int my) {
        if (is_connected) disconnect_btn.mouse_up(mx, my);
    }

    public void cancel_press() {
        disconnect_btn.cancel_press();
    }

    public void render(Context ctx) {
        if (selected) {
            ctx.draw_rect_rounded(rx + 6, ry + 3, rw - 12, rh - 6, 9f, sel_bg_col);
        } else if (hovered) {
            ctx.draw_rect_rounded(rx + 6, ry + 3, rw - 12, rh - 6, 9f, hov_bg_col);
        }

        signal_bars.render(ctx, rx + PAD, ry + rh - 6, signal_val);

        pdt(ctx, ssid, rx + PAD + 32, ry + (rh - 15) / 2, 15f,
            is_connected ? conn_name_col : norm_name_col);

        int icon_rx = rx + rw - PAD - 4;

        if (is_connected) {
            int db_x = icon_rx - 22;
            int db_y = ry + (rh - 18) / 2;
            disconnect_btn.set_bounds(db_x, db_y, 22, 18);
            disconnect_btn.render(ctx);
            icon_rx -= 30;
        }

        if (security != "--" && security != "") {
            pdt(ctx, "🔒", icon_rx - 14, ry + (rh - 12) / 2, 11f, lock_col);
        }
    }
}
