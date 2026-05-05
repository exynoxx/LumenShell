using DrawKit;
using GLib;

/**
 * WiFiPage — full-panel WiFi manager.
 *
 * Renders inside the rectangle passed to render() each frame:
 *   • Header bar: "WiFi" title + live connection chip
 *   • Scrollable network list with 4-bar signal indicators, lock icons,
 *     connected-network highlight
 *   • Inline password field + Connect button when a network is selected
 *
 * Background nmcli scanning is done on a worker thread so the UI never
 * blocks.  Keyboard input for the password field is registered directly
 * with WLHooks while the field is focused.
 */
public class WifiPage : GLib.Object, ITrayPage {

    // ── Layout constants ──────────────────────────────────────────────────
    private const int PAD       = 14;
    private const int HEADER_H  = 44;
    private const int ROW_H     = 36;
    private const int PASS_H    = 54;
    private const int MAX_NETS  = 8;

    // ── WiFi network record ───────────────────────────────────────────────
    private class Net {
        public string ssid;
        public int    signal;
        public string security;
        public Net(string s, int sig, string sec) {
            ssid = s;  signal = sig;  security = sec;
        }
    }

    // ── State ─────────────────────────────────────────────────────────────
    private Net[]  nets          = {};
    private string connected     = "";
    private int    hovered_row   = -1;
    private int    selected_row  = -1;
    private string password      = "";
    private bool   pass_focused  = false;
    private bool   connect_hov   = false;
    private bool   scanning      = false;

    // Bounds from last render() call — used for hit-testing
    private int px;
    private int py;
    private int pw;
    private int ph;

    // ─────────────────────────────────────────────────────────────────────
    // ITrayPage
    // ─────────────────────────────────────────────────────────────────────

    public string get_title() { return "WiFi"; }

    public void on_activate() {
        nets        = {};
        selected_row = -1;
        password    = "";
        pass_focused = false;
        connect_hov  = false;
        scanning    = true;
        fetch_connected();
        new GLib.Thread<void>("wifi-scan", () => {
            nets    = fetch_nets();
            scanning = false;
            redraw  = true;
        });
    }

    public void on_deactivate() {
        dismiss_pass();
    }

    public void mouse_up(int mx, int my) {}

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    public void render(Context ctx, int x, int y, int w, int h) {
        px = x;  py = y;  pw = w;  ph = h;

        // ── Header ───────────────────────────────────────────────────────
        int title_top = y + (HEADER_H - 20) / 2;
        pdt(ctx, "WiFi", x + PAD, title_top, 20f, {1f, 1f, 1f, 1f});

        // Connection status chip (right-aligned)
        bool is_conn    = connected != "" && connected != "--";
        string chip_txt = is_conn ? "●  " + connected : "●  Offline";
        Color  chip_col = is_conn
            ? Color(){r=0.18f, g=0.88f, b=0.42f, a=1f}
            : Color(){r=0.52f, g=0.52f, b=0.57f, a=1f};
        float chip_sz  = 12.5f;
        int   chip_tw  = ctx.width_of(chip_txt, chip_sz);
        int   chip_pad = 10;
        int   chip_h   = 24;
        int   chip_x   = x + w - PAD - chip_tw - chip_pad * 2;
        int   chip_y   = y + (HEADER_H - chip_h) / 2;
        ctx.draw_rect_rounded(chip_x, chip_y, chip_tw + chip_pad * 2, chip_h, 12f,
            Color(){r=0.11f, g=0.13f, b=0.19f, a=1f});
        pdt(ctx, chip_txt, chip_x + chip_pad, chip_y + (chip_h - (int)chip_sz) / 2,
            chip_sz, chip_col);

        // Separator
        int sep_y = y + HEADER_H;
        ctx.draw_rect(x + PAD, sep_y, w - PAD * 2, 1,
            Color(){r=0.22f, g=0.24f, b=0.35f, a=0.7f});

        // ── Network list ─────────────────────────────────────────────────
        int list_top = sep_y + 6;
        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_avail   = h - HEADER_H - 6 - pass_reserve;
        int max_rows     = list_avail / ROW_H;

        if (scanning && nets.length == 0) {
            // Scanning indicator
            pdt_center(ctx, "Scanning for networks…",
                x + w / 2, list_top + (list_avail - 14) / 2,
                14f, Color(){r=0.52f, g=0.54f, b=0.62f, a=1f});
        } else if (nets.length == 0) {
            pdt_center(ctx, "No networks found",
                x + w / 2, list_top + (list_avail - 14) / 2,
                14f, Color(){r=0.45f, g=0.46f, b=0.52f, a=1f});
        } else {
            for (int i = 0; i < nets.length && i < max_rows; i++) {
                render_row(ctx, i, x, list_top + i * ROW_H, w, ROW_H);
            }
        }

        // ── Password area ─────────────────────────────────────────────────
        if (selected_row >= 0 && selected_row < nets.length) {
            render_pass(ctx, x, y + h - PASS_H, w, PASS_H);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Row rendering
    // ─────────────────────────────────────────────────────────────────────

    private void render_row(Context ctx, int i, int x, int y, int w, int h) {
        var   net     = nets[i];
        bool  hov     = hovered_row == i;
        bool  sel     = selected_row == i;
        bool  is_conn = net.ssid == connected;

        // Row background
        if (sel) {
            ctx.draw_rect_rounded(x + 6, y + 3, w - 12, h - 6, 9f,
                Color(){r=0.10f, g=0.24f, b=0.62f, a=0.88f});
        } else if (hov) {
            ctx.draw_rect_rounded(x + 6, y + 3, w - 12, h - 6, 9f,
                Color(){r=0.17f, g=0.18f, b=0.24f, a=0.85f});
        }

        // Signal bars
        draw_signal_bars(ctx, x + PAD, y + h - 6, net.signal);

        // SSID
        Color name_col = is_conn
            ? Color(){r=0.18f, g=0.88f, b=0.42f, a=1f}
            : Color(){r=0.90f, g=0.91f, b=0.94f, a=1f};
        pdt(ctx, net.ssid, x + PAD + 32, y + (h - 15) / 2, 15f, name_col);

        // Right-side icons (work right-to-left)
        int rx = x + w - PAD - 4;

        if (is_conn) {
            pdt(ctx, "✓", rx - 14, y + (h - 14) / 2, 14f,
                Color(){r=0.18f, g=0.88f, b=0.42f, a=1f});
            rx -= 22;
        }
        if (net.security != "--" && net.security != "") {
            pdt(ctx, "🔒", rx - 14, y + (h - 12) / 2, 11f,
                Color(){r=0.52f, g=0.52f, b=0.58f, a=1f});
        }
    }

    /**
     * Draw 4 vertical WiFi signal bars.
     * bottom_y is the baseline (bottom edge of the bar group).
     */
    private void draw_signal_bars(Context ctx, int left_x, int bottom_y, int signal) {
        int active_bars = signal >= 75 ? 4 : signal >= 50 ? 3 : signal >= 25 ? 2 : 1;

        Color active_col = signal >= 65
            ? Color(){r=0.18f, g=0.85f, b=0.40f, a=1f}
            : signal >= 35
                ? Color(){r=1.0f, g=0.72f, b=0.10f, a=1f}
                : Color(){r=1.0f, g=0.30f, b=0.30f, a=1f};
        Color dim_col = Color(){r=0.20f, g=0.21f, b=0.28f, a=0.75f};

        int[] heights = { 6, 10, 14, 20 };

        for (int b = 0; b < 4; b++) {
            int bh = heights[b];
            int bx = left_x + b * 7;
            int by = bottom_y - bh;
            ctx.draw_rect_rounded(bx, by, 4, bh, 2f,
                b < active_bars ? active_col : dim_col);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Password area
    // ─────────────────────────────────────────────────────────────────────

    private void render_pass(Context ctx, int x, int y, int w, int h) {
        // Thin separator
        ctx.draw_rect(x + PAD, y + 1, w - PAD * 2, 1,
            Color(){r=0.22f, g=0.24f, b=0.35f, a=0.5f});

        int field_w = w - PAD * 2 - 90 - 10;
        int field_x = x + PAD;
        int field_y = y + (h - 34) / 2;

        // Password field
        Color field_bg = pass_focused
            ? Color(){r=0.14f, g=0.16f, b=0.24f, a=1f}
            : Color(){r=0.10f, g=0.11f, b=0.16f, a=1f};
        ctx.draw_rect_rounded(field_x, field_y, field_w, 34, 8f, field_bg);

        // Border glow when focused
        if (pass_focused) {
            ctx.draw_rect_rounded(field_x - 1, field_y - 1, field_w + 2, 36, 9f,
                Color(){r=0.22f, g=0.48f, b=1.0f, a=0.55f});
            ctx.draw_rect_rounded(field_x, field_y, field_w, 34, 8f, field_bg);
        }

        // Masked text or placeholder
        var sb = new GLib.StringBuilder();
        for (int i = 0; i < password.length; i++) sb.append_unichar('●');
        string display  = sb.str != "" ? sb.str : "Password…";
        Color  text_col = sb.str != ""
            ? Color(){r=1f, g=1f, b=1f, a=0.92f}
            : Color(){r=0.42f, g=0.43f, b=0.50f, a=0.85f};
        pdt(ctx, display, field_x + 10, field_y + (34 - 13) / 2, 13f, text_col);

        // Blinking cursor
        if (pass_focused) {
            int cursor_x = field_x + 10 + ctx.width_of(sb.str, 13f);
            ctx.draw_rect(cursor_x, field_y + 7, 2, 20,
                Color(){r=0.50f, g=0.65f, b=1.0f, a=0.9f});
        }

        // Connect button
        int btn_x = x + w - PAD - 90;
        int btn_y = y + (h - 34) / 2;
        Color btn_col = connect_hov
            ? Color(){r=0.20f, g=0.50f, b=1.0f, a=1f}
            : Color(){r=0.12f, g=0.34f, b=0.88f, a=1f};
        ctx.draw_rect_rounded(btn_x, btn_y, 90, 34, 8f, btn_col);
        pdt_center(ctx, "Connect", btn_x + 45, btn_y + (34 - 14) / 2, 14f,
            Color(){r=1f, g=1f, b=1f, a=1f});
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mouse handling
    // ─────────────────────────────────────────────────────────────────────

    public void mouse_motion(int mx, int my) {
        int old_hr  = hovered_row;
        bool old_ch = connect_hov;

        hovered_row = -1;
        connect_hov = false;

        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_avail   = ph - HEADER_H - 6 - pass_reserve;
        int max_rows     = list_avail / ROW_H;
        int list_top     = py + HEADER_H + 6;

        for (int i = 0; i < nets.length && i < max_rows; i++) {
            int ry = list_top + i * ROW_H;
            if (mx >= px + 6 && mx <= px + pw - 6 && my >= ry && my < ry + ROW_H) {
                hovered_row = i;
                break;
            }
        }

        if (selected_row >= 0) {
            int btn_x = px + pw - PAD - 90;
            int btn_y = py + ph - PASS_H + (PASS_H - 34) / 2;
            connect_hov = mx >= btn_x && mx <= btn_x + 90
                       && my >= btn_y && my <= btn_y + 34;
        }

        if (hovered_row != old_hr || connect_hov != old_ch)
            redraw = true;
    }

    public void mouse_down(int mx, int my) {
        // Connect button
        if (connect_hov) {
            do_connect();
            return;
        }

        // Password field click → focus
        if (selected_row >= 0) {
            int field_x = px + PAD;
            int field_w = pw - PAD * 2 - 90 - 10;
            int field_y = py + ph - PASS_H + (PASS_H - 34) / 2;
            if (mx >= field_x && mx <= field_x + field_w
             && my >= field_y && my <= field_y + 34) {
                pass_focused = true;
                WLHooks.register_on_key_down(key_handler);
                redraw = true;
                return;
            }
        }

        // Network row click
        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_avail   = ph - HEADER_H - 6 - pass_reserve;
        int max_rows     = list_avail / ROW_H;
        int list_top     = py + HEADER_H + 6;

        for (int i = 0; i < nets.length && i < max_rows; i++) {
            int ry = list_top + i * ROW_H;
            if (mx >= px + 6 && mx <= px + pw - 6 && my >= ry && my < ry + ROW_H) {
                if (selected_row == i) {
                    dismiss_pass();
                } else {
                    selected_row = i;
                    password     = "";
                    pass_focused = true;
                    WLHooks.register_on_key_down(key_handler);
                }
                redraw = true;
                return;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Keyboard
    // ─────────────────────────────────────────────────────────────────────

    private void key_handler(uint32 keysym) {
        if (!pass_focused) return;
        if (keysym == 0xFF08) {                              // BackSpace
            if (password.length > 0)
                password = password.substring(0, password.length - 1);
        } else if (keysym == 0xFF0D || keysym == 0xFF8D) {  // Return / KP_Enter
            do_connect();
            return;
        } else if (keysym == 0xFF1B) {                      // Escape
            dismiss_pass();
        } else if (keysym >= 0x20 && keysym <= 0x7E) {      // Printable ASCII
            password += ((unichar) keysym).to_string();
        }
        redraw = true;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Network actions
    // ─────────────────────────────────────────────────────────────────────

    private void do_connect() {
        if (selected_row < 0 || selected_row >= nets.length) return;
        var    net  = nets[selected_row];
        string ssid = net.ssid.replace("\\", "\\\\").replace("\"", "\\\"");
        string cmd;
        if (password == "") {
            cmd = @"nmcli connection up id \"$ssid\"";
        } else {
            string pw = password.replace("\\", "\\\\").replace("\"", "\\\"");
            cmd = @"nmcli device wifi connect \"$ssid\" password \"$pw\"";
        }
        try { Process.spawn_command_line_async(cmd); } catch (SpawnError e) {}
        dismiss_pass();
        GLib.Timeout.add(3000, () => { fetch_connected(); redraw = true; return false; });
    }

    private void dismiss_pass() {
        selected_row = -1;
        password     = "";
        pass_focused = false;
        WLHooks.register_on_key_down(null);
    }

    // ─────────────────────────────────────────────────────────────────────
    // nmcli helpers
    // ─────────────────────────────────────────────────────────────────────

    private void fetch_connected() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device",
                out out_str, null, null);
        } catch (SpawnError e) { return; }
        connected = "";
        foreach (var line in out_str.split("\n")) {
            var p = line.split(":");
            if (p.length >= 4 && p[1] == "wifi" && p[2] == "connected") {
                connected = p[3];
                break;
            }
        }
    }

    private Net[] fetch_nets() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list",
                out out_str, null, null);
        } catch (SpawnError e) { return {}; }

        Net[] result = {};
        var seen = new GLib.HashTable<string, bool>(str_hash, str_equal);
        foreach (var line in out_str.split("\n")) {
            var p = line.split(":");
            if (p.length < 3) continue;
            string ssid = p[0].strip();
            if (ssid == "" || ssid == "--") continue;
            if (seen.contains(ssid)) continue;
            seen.insert(ssid, true);
            result += new Net(ssid, int.parse(p[1]), p[2]);
            if (result.length >= MAX_NETS) break;
        }
        return result;
    }
}
