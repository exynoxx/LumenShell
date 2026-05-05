using Gee;
using GLib;
using DrawKit;

public class WifiTray : IconAndText, IClickable, IUpdateable {

    // Panel layout constants
    private const int PANEL_W      = 270;
    private const int PANEL_MAX_H  = 240;   // fits in TRAY_Y (≈246px) above tray bar
    private const int HEADER_H     = 38;
    private const int ROW_H        = 32;
    private const int MAX_NETS     = 5;
    private const int PAD          = 10;
    private const int PASS_ROW_H   = 46;

    private class WifiNetwork {
        public string ssid;
        public int    signal;
        public string security;
        public WifiNetwork(string ssid, int signal, string security) {
            this.ssid     = ssid;
            this.signal   = signal;
            this.security = security;
        }
    }

    private WifiNetwork[] networks     = {};
    private string connected_ssid      = "";
    private int    hovered_net         = -1;
    private int    selected_net        = -1;
    private string password_buf        = "";
    private bool   pass_focused        = false;
    private bool   connect_btn_hovered = false;
    private bool   scanning            = false;

    public WifiTray(Context ctx) {
        base(ctx, new HoverableIcon("wifi-unknown"), "No WiFi", PANEL_MAX_H);
        update();
    }

    // ── IClickable ──────────────────────────────────────────────────────────

    public void mouse_down() {
        if (icon.hovered) {
            if (!opened) {
                networks = {};
                selected_net = -1;
                password_buf = "";
                scanning = true;
                new GLib.Thread<void>("wifi-scan", () => {
                    var result = fetch_networks();
                    networks = result;
                    scanning = false;
                    redraw = true;
                });
            }
            handle_icon_click();
            if (!opened) dismiss_password();
        } else if (opened && in_panel(last_mx, last_my)) {
            handle_panel_click(last_mx, last_my);
        } else if (opened) {
            close_panel();
            dismiss_password();
        }
    }

    public void mouse_up() {}

    // ── IUpdateable ─────────────────────────────────────────────────────────

    public string get_status() { return connected_ssid; }

    public void update() {
        string stdout_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device",
                out stdout_str, null, null);
        } catch (SpawnError e) { return; }

        connected_ssid = "";
        foreach (var line in stdout_str.split("\n")) {
            var p = line.split(":");
            if (p.length >= 4 && p[1] == "wifi" && p[2] == "connected") {
                connected_ssid = p[3];
                break;
            }
        }

        icon.free();
        if (connected_ssid != "" && connected_ssid != "--") {
            icon.load("wifi");
        } else {
            icon.load("nowifi");
        }
    }

    // ── Mouse motion (panel hover tracking) ─────────────────────────────────

    public override void mouse_motion(int mx, int my) {
        base.mouse_motion(mx, my);
        if (!opened) return;

        int old_hn  = hovered_net;
        bool old_cb = connect_btn_hovered;
        hovered_net         = -1;
        connect_btn_hovered = false;

        int px    = panel_x();
        int p_top = Tray.TRAY_Y - PANEL_MAX_H;
        int nets_y = p_top + HEADER_H;

        for (int i = 0; i < networks.length; i++) {
            int ry = nets_y + i * ROW_H;
            if (mx >= px && mx <= px + PANEL_W && my >= ry && my < ry + ROW_H) {
                hovered_net = i;
                break;
            }
        }

        if (selected_net >= 0) {
            int pass_y = nets_y + networks.length * ROW_H + PAD;
            int bx = px + PANEL_W - 78;
            int by = pass_y + (PASS_ROW_H - 26) / 2;
            connect_btn_hovered = mx >= bx && mx <= bx + 68
                               && my >= by && my <= by + 26;
        }

        if (hovered_net != old_hn || connect_btn_hovered != old_cb)
            redraw = true;
    }

    // ── Rendering ───────────────────────────────────────────────────────────

    public override void render(Context ctx) {
        // Tint icon based on connection state; hover overrides to B&W anyway
        if (!icon.hovered) {
            if (connected_ssid != "" && connected_ssid != "--")
                ctx.set_tex_color({0.25f, 1.0f, 0.45f, 1.0f}); // green
            else
                ctx.set_tex_color({0.45f, 0.45f, 0.45f, 1.0f}); // grey
        }
        icon.render(ctx);
        ctx.set_tex_color({1, 1, 1, 1});

        if (panel_height > 0)
            render_panel(ctx);
    }

    protected override void render_panel(Context ctx) {
        int px     = panel_x();
        int p_top  = Tray.TRAY_Y - PANEL_MAX_H;  // fully-open top
        int clip_y = Tray.TRAY_Y - panel_height;  // current animated top

        // Clip content to animated panel height
        ctx.stencil_push();
        ctx.draw_rect(px, clip_y, PANEL_W, panel_height, {1, 1, 1, 1});
        ctx.stencil_apply();

        // Background
        ctx.draw_rect_rounded(px, p_top, PANEL_W, PANEL_MAX_H, 12,
            {0.07f, 0.07f, 0.09f, 0.97f});

        // ── Header ──────────────────────────────────────────────────────
        bool connected = connected_ssid != "" && connected_ssid != "--";
        Color hdr_col  = connected
            ? Color(){r=0.25f, g=1.0f,  b=0.45f, a=1}
            : Color(){r=0.55f, g=0.55f, b=0.55f, a=1};

        string hdr_text = scanning
            ? "WiFi  ·  Scanning…"
            : connected
                ? "WiFi  ·  " + connected_ssid
                : "WiFi  ·  Not connected";

        dtl(ctx, hdr_text, px + PAD, p_top + 10, 13, hdr_col);

        // Divider
        ctx.draw_rect(px + PAD, p_top + HEADER_H - 5,
            PANEL_W - PAD * 2, 1, {0.3f, 0.3f, 0.3f, 0.7f});

        // ── Network rows ────────────────────────────────────────────────
        int nets_y = p_top + HEADER_H;

        for (int i = 0; i < networks.length; i++) {
            var net = networks[i];
            int ry  = nets_y + i * ROW_H;
            bool hov = hovered_net == i;
            bool sel = selected_net == i;

            if (hov || sel) {
                ctx.draw_rect_rounded(px + 4, ry + 2, PANEL_W - 8, ROW_H - 4, 6,
                    sel ? Color(){r=0.12f, g=0.28f, b=0.62f, a=0.9f}
                        : Color(){r=0.2f,  g=0.2f,  b=0.25f, a=0.7f});
            }

            // Signal dot: green / yellow / red
            float s = net.signal / 100.0f;
            Color sig = s > 0.6f
                ? Color(){r=0.25f, g=1.0f, b=0.4f, a=1}
                : s > 0.3f
                    ? Color(){r=1.0f, g=0.75f, b=0.2f, a=1}
                    : Color(){r=1.0f, g=0.35f, b=0.3f, a=1};
            ctx.draw_circle(px + PAD + 5, ry + ROW_H / 2, 4, sig);

            // SSID
            Color name_col = net.ssid == connected_ssid
                ? Color(){r=0.25f, g=1.0f, b=0.45f, a=1}
                : Color(){r=1,     g=1,    b=1,     a=1};
            dtl(ctx, net.ssid, px + PAD + 16, ry + (ROW_H - 13) / 2, 13, name_col);

            // Lock for secured networks
            if (net.security != "--" && net.security != "") {
                dtl(ctx, "🔒", px + PANEL_W - 22, ry + (ROW_H - 11) / 2, 11,
                    Color(){r=0.65f, g=0.65f, b=0.65f, a=1});
            }
        }

        // ── Password row ────────────────────────────────────────────────
        if (selected_net >= 0 && selected_net < networks.length) {
            int pass_y = nets_y + networks.length * ROW_H + PAD;

            // Input field background
            int field_w = PANEL_W - PAD * 2 - 78;
            ctx.draw_rect_rounded(px + PAD, pass_y, field_w, PASS_ROW_H - 8, 6,
                Color(){r=0.16f, g=0.16f, b=0.20f, a=1});

            // Masked password text
            var sb = new GLib.StringBuilder();
            for (int i = 0; i < password_buf.length; i++) sb.append_unichar('●');
            string masked = sb.str;
            dtl(ctx,
                masked.length > 0 ? masked : "password",
                px + PAD + 6, pass_y + (PASS_ROW_H - 8 - 12) / 2, 12,
                masked.length > 0
                    ? Color(){r=1,    g=1,    b=1,    a=0.9f}
                    : Color(){r=0.5f, g=0.5f, b=0.5f, a=0.7f});

            // Connect button
            int bx = px + PANEL_W - 78;
            int by = pass_y + (PASS_ROW_H - 8 - 26) / 2;
            Color btn = connect_btn_hovered
                ? Color(){r=0.25f, g=0.55f, b=1.0f, a=1}
                : Color(){r=0.15f, g=0.38f, b=0.82f, a=1};
            ctx.draw_rect_rounded(bx, by, 68, 26, 6, btn);
            dtl(ctx, "Connect", bx + 5, by + (26 - 12) / 2, 12, Color(){r=1, g=1, b=1, a=1});
        }

        ctx.stencil_pop();
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    // draw_text in libdrawkit: x = horizontal CENTER of text, y = baseline.
    // This helper lets us pass left-edge + visual-top instead.
    // ascender ≈ font_size * 0.82 converts top→baseline.
    private void dtl(Context ctx, string text, int left, int top, float size, Color col) {
        int w = ctx.width_of(text, size);
        ctx.draw_text(text, left + w / 2, top + (int)(size * 0.82f), size, col);
    }

    private int panel_x() {
        // Right-align panel with right edge of the icon
        return this.x + width - PANEL_W;
    }

    private bool in_panel(int mx, int my) {
        int px = panel_x();
        int py = Tray.TRAY_Y - panel_height;
        return mx >= px && mx <= px + PANEL_W
            && my >= py && my <= Tray.TRAY_Y;
    }

    private void handle_panel_click(int mx, int my) {
        if (connect_btn_hovered) {
            connect_to_selected();
            return;
        }

        int nets_y = (Tray.TRAY_Y - PANEL_MAX_H) + HEADER_H;
        for (int i = 0; i < networks.length; i++) {
            int ry = nets_y + i * ROW_H;
            if (my >= ry && my < ry + ROW_H) {
                if (selected_net == i) {
                    selected_net = -1;
                    dismiss_password();
                } else {
                    selected_net        = i;
                    password_buf        = "";
                    pass_focused        = true;
                    WLHooks.register_on_key_down(on_key_input);
                }
                redraw = true;
                return;
            }
        }
    }

    private void dismiss_password() {
        selected_net = -1;
        password_buf = "";
        pass_focused = false;
        WLHooks.register_on_key_down(null);
    }

    private void connect_to_selected() {
        if (selected_net < 0 || selected_net >= networks.length) return;
        var net = networks[selected_net];
        string ssid_safe = net.ssid.replace("\\", "\\\\").replace("\"", "\\\"");
        string cmd;
        if (password_buf == "") {
            cmd = @"nmcli connection up id \"$ssid_safe\"";
        } else {
            string pw_safe = password_buf.replace("\\", "\\\\").replace("\"", "\\\"");
            cmd = @"nmcli device wifi connect \"$ssid_safe\" password \"$pw_safe\"";
        }
        try {
            Process.spawn_command_line_async(cmd);
        } catch (SpawnError e) {
            stderr.printf("WiFi connect: %s\n", e.message);
        }
        close_panel();
        dismiss_password();
        GLib.Timeout.add(3000, () => { update(); redraw = true; return false; });
    }

    public void on_key_input(uint32 keysym) {
        if (!pass_focused) return;
        if (keysym == 0xFF08) {                          // BackSpace
            if (password_buf.length > 0)
                password_buf = password_buf.substring(0, password_buf.length - 1);
        } else if (keysym == 0xFF0D || keysym == 0xFF8D) { // Return / KP_Enter
            connect_to_selected();
        } else if (keysym == 0xFF1B) {                   // Escape
            dismiss_password();
            close_panel();
        } else if (keysym >= 0x20 && keysym <= 0x7E) {  // printable ASCII
            password_buf += ((unichar) keysym).to_string();
        }
        redraw = true;
    }

    private WifiNetwork[] fetch_networks() {
        string stdout_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list",
                out stdout_str, null, null);
        } catch (SpawnError e) { return {}; }

        WifiNetwork[] result = {};
        // De-duplicate SSIDs
        var seen = new GLib.HashTable<string, bool>(str_hash, str_equal);
        foreach (var line in stdout_str.split("\n")) {
            var p = line.split(":");
            if (p.length < 3) continue;
            string ssid = p[0].strip();
            if (ssid == "" || ssid == "--") continue;
            if (seen.contains(ssid)) continue;
            seen.insert(ssid, true);
            result += new WifiNetwork(ssid, int.parse(p[1]), p[2]);
            if (result.length >= MAX_NETS) break;
        }
        return result;
    }
}
