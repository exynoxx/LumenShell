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

    public signal void state_changed();
    private const bool DEBUG_WIFI = false;

    // ── Layout constants ──────────────────────────────────────────────────
    private const int PAD       = 14;
    private const int HEADER_H  = 44;
    private const int ROW_H     = 36;
    private const int PASS_H    = 54;

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
    private int    disconnect_hov_row = -1;
    private bool   scanning      = false;
    private UiScrollView list_view = new UiScrollView();
    private UiSignalBars signal_bars = new UiSignalBars();
    private UiButton refresh_button = new UiButton();
    private UiButton connect_button = new UiButton();
    private UiButton disconnect_button = new UiButton();
    private UiTextField password_field = new UiTextField();

    // Tracks last rendered connect-button mode to avoid per-frame color reassignment
    private bool connect_btn_is_disconnect = false;

    // Bounds from last render() call — used for hit-testing
    private int px;
    private int py;
    private int pw;
    private int ph;

    public WifiPage() {
        refresh_button.label = "Refresh";
        refresh_button.text_size = 12f;
        refresh_button.normal_color = Color(){r=0.14f, g=0.21f, b=0.40f, a=1f};
        refresh_button.hover_color = Color(){r=0.20f, g=0.30f, b=0.56f, a=1f};
        refresh_button.pressed_color = Color(){r=0.11f, g=0.17f, b=0.32f, a=1f};
        refresh_button.clicked.connect(() => {
            refresh_nets_async(true);
            redraw = true;
        });

        connect_button.label = "Connect";
        connect_button.text_size = 14f;
        connect_button.normal_color  = Color(){r=0.12f, g=0.34f, b=0.88f, a=1f};
        connect_button.hover_color   = Color(){r=0.20f, g=0.50f, b=1.0f,  a=1f};
        connect_button.pressed_color = Color(){r=0.10f, g=0.28f, b=0.72f, a=1f};
        connect_button.clicked.connect(() => {
            if (selected_row >= 0 && selected_row < nets.length
             && nets[selected_row].ssid == connected) {
                do_disconnect();
            } else {
                do_connect();
            }
        });

        disconnect_button.label = "×";
        disconnect_button.text_size = 13f;
        disconnect_button.radius = 6f;
        disconnect_button.normal_color = Color(){r=0.74f, g=0.20f, b=0.20f, a=0.96f};
        disconnect_button.hover_color = Color(){r=0.90f, g=0.30f, b=0.30f, a=1f};
        disconnect_button.pressed_color = Color(){r=0.66f, g=0.16f, b=0.16f, a=1f};
        disconnect_button.clicked.connect(() => {
            do_disconnect();
        });

        password_field.placeholder = "Password…";
        password_field.changed.connect((s) => {
            redraw = true;
        });
        password_field.submitted.connect(() => {
            do_connect();
        });
        password_field.cancelled.connect(() => {
            dismiss_pass();
            redraw = true;
        });
        password_field.focus_changed.connect((focused) => {
            redraw = true;
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    // ITrayPage
    // ─────────────────────────────────────────────────────────────────────

    public string get_title() { return "WiFi"; }

    public void on_activate() {
        if (DEBUG_WIFI) print("[wifi] on_activate()\n");
        nets        = {};
        selected_row = -1;
        scanning    = true;
        connected   = "";
        hovered_row = -1;
        disconnect_hov_row = -1;
        list_view.reset();
        password_field.set_text("");
        password_field.blur();
        connect_button.cancel_press();
        disconnect_button.cancel_press();
        refresh_nets_async(false);
    }

    public void on_deactivate() {
        dismiss_pass();
    }

    public void mouse_up(int mx, int my) {
        refresh_button.mouse_up(mx, my);
        connect_button.mouse_up(mx, my);
        disconnect_button.mouse_up(mx, my);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    public void render(Context ctx, int x, int y, int w, int h) {
        px = x;  py = y;  pw = w;  ph = h;

        // ── Header ───────────────────────────────────────────────────────
        int title_top = y + (HEADER_H - 20) / 2;
        pdt(ctx, "WiFi", x + PAD, title_top, 20f, {1f, 1f, 1f, 1f});

        // Refresh button
        int refresh_w = 78;
        int refresh_h = 24;
        int refresh_x = x + PAD + 58;
        int refresh_y = y + (HEADER_H - refresh_h) / 2;
        refresh_button.set_bounds(refresh_x, refresh_y, refresh_w, refresh_h);
        refresh_button.label = scanning ? "Scanning" : "Refresh";
        refresh_button.render(ctx);

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
        list_view.update_layout(x + 6, list_top, w - 12, list_avail, ROW_H, nets.length);

        if (selected_row >= 0)
            list_view.ensure_visible(selected_row);

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
            int first = list_view.first_visible_row();
            int rows  = list_view.visible_rows();
            for (int rel = 0; rel < rows; rel++) {
                int i = first + rel;
                if (i >= nets.length) break;
                render_row(ctx, i, x, list_top + rel * ROW_H, w, ROW_H);
            }
            list_view.render(ctx);
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
        signal_bars.render(ctx, x + PAD, y + h - 6, net.signal);

        // SSID
        Color name_col = is_conn
            ? Color(){r=0.18f, g=0.88f, b=0.42f, a=1f}
            : Color(){r=0.90f, g=0.91f, b=0.94f, a=1f};
        pdt(ctx, net.ssid, x + PAD + 32, y + (h - 15) / 2, 15f, name_col);

        // Right-side icons (work right-to-left)
        int rx = x + w - PAD - 4;

        if (is_conn) {
            int db_w = 22;
            int db_h = 18;
            int db_x = rx - db_w;
            int db_y = y + (h - db_h) / 2;
            disconnect_button.set_bounds(db_x, db_y, db_w, db_h);
            disconnect_button.render(ctx);
            rx -= 30;
        }
        if (net.security != "--" && net.security != "") {
            pdt(ctx, "🔒", rx - 14, y + (h - 12) / 2, 11f,
                Color(){r=0.52f, g=0.52f, b=0.58f, a=1f});
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Password area
    // ─────────────────────────────────────────────────────────────────────

    private void render_pass(Context ctx, int x, int y, int w, int h) {
        // Thin separator
        ctx.draw_rect(x + PAD, y + 1, w - PAD * 2, 1,
            Color(){r=0.22f, g=0.24f, b=0.35f, a=0.5f});

        bool is_conn_row = selected_row >= 0
                        && selected_row < nets.length
                        && nets[selected_row].ssid == connected;

        if (is_conn_row) {
            int btn_w = 120;
            int btn_x = x + w - PAD - btn_w;
            int btn_y = y + (h - 34) / 2;

            pdt(ctx, "Connected", x + PAD, btn_y + (34 - 13) / 2, 13f,
                Color(){r=0.58f, g=0.78f, b=0.62f, a=0.95f});

            if (!connect_btn_is_disconnect) {
                connect_btn_is_disconnect = true;
                connect_button.label         = "Disconnect";
                connect_button.normal_color  = Color(){r=0.76f, g=0.20f, b=0.20f, a=1f};
                connect_button.hover_color   = Color(){r=0.88f, g=0.26f, b=0.26f, a=1f};
                connect_button.pressed_color = Color(){r=0.64f, g=0.16f, b=0.16f, a=1f};
            }
            connect_button.set_bounds(btn_x, btn_y, btn_w, 34);
            connect_button.render(ctx);
            return;
        }

        int field_w = w - PAD * 2 - 90 - 10;
        int field_x = x + PAD;
        int field_y = y + (h - 34) / 2;

        password_field.set_bounds(field_x, field_y, field_w, 34);
        password_field.render(ctx);

        if (connect_btn_is_disconnect) {
            connect_btn_is_disconnect = false;
            connect_button.label         = "Connect";
            connect_button.normal_color  = Color(){r=0.12f, g=0.34f, b=0.88f, a=1f};
            connect_button.hover_color   = Color(){r=0.20f, g=0.50f, b=1.0f,  a=1f};
            connect_button.pressed_color = Color(){r=0.10f, g=0.28f, b=0.72f, a=1f};
        }
        // Connect button
        int btn_x = x + w - PAD - 90;
        int btn_y = y + (h - 34) / 2;
        connect_button.set_bounds(btn_x, btn_y, 90, 34);
        connect_button.render(ctx);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mouse handling
    // ─────────────────────────────────────────────────────────────────────

    public void mouse_motion(int mx, int my) {
        refresh_button.mouse_motion(mx, my);
        disconnect_button.mouse_motion(mx, my);
        connect_button.mouse_motion(mx, my);    
        password_field.mouse_motion(mx, my);

        update_list_viewport_geometry();
        hovered_row = list_view.row_at(mx, my);
    }

    public void mouse_down(int mx, int my) {
        refresh_button.mouse_down(mx, my);

        if (disconnect_hov_row >= 0) {
            disconnect_button.mouse_down(mx, my);
        }

        if (selected_row >= 0 && selected_row < nets.length) {
            bool is_conn_row = nets[selected_row].ssid == connected;

            if (!is_conn_row) {
                password_field.mouse_down(mx, my);
            }

            connect_button.mouse_down(mx, my);
        }

        // Network row click
        update_list_viewport_geometry();
        int i = list_view.row_at(mx, my);
        if (i >= 0) {
            if (selected_row == i) {
                dismiss_pass();
            } else {
                selected_row = i;
                password_field.set_text("");

                if (nets[selected_row].ssid == connected)
                    password_field.blur();
                else
                    password_field.focus();

                update_list_viewport_geometry();
                list_view.ensure_visible(selected_row);
            }
            redraw = true;
            return;
        }

        if (password_field.focused) {
            password_field.blur();
            redraw = true;
        }
    }

    public void mouse_scroll(int mx, int my, int amount) {
        if (amount == 0) return;

        update_list_viewport_geometry();
        if (!list_view.contains(mx, my) || !list_view.can_scroll()) return;

        if (list_view.scroll_lines(amount)) {
            hovered_row = list_view.row_at(mx, my);
            redraw = true;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Network actions
    // ─────────────────────────────────────────────────────────────────────

    private void do_connect() {
        if (selected_row < 0 || selected_row >= nets.length) return;
        var    net  = nets[selected_row];
        string ssid = net.ssid.replace("\\", "\\\\").replace("\"", "\\\"");
        string cmd;
        if (password_field.get_text() == "") {
            cmd = @"nmcli connection up id \"$ssid\"";
        } else {
            string pw = password_field.get_text().replace("\\", "\\\\").replace("\"", "\\\"");
            cmd = @"nmcli device wifi connect \"$ssid\" password \"$pw\"";
        }
        if (DEBUG_WIFI) print("[wifi] connect cmd: %s\n", cmd);
        try { Process.spawn_command_line_async(cmd); } catch (SpawnError e) {}
        dismiss_pass();
        delayed_refresh(1400, true);
    }

    private void do_disconnect() {
        string dev = get_wifi_device();
        if (dev == "") return;

        string cmd = @"nmcli device disconnect \"$dev\"";
        if (DEBUG_WIFI) print("[wifi] disconnect cmd: %s\n", cmd);
        try { Process.spawn_command_line_async(cmd); } catch (SpawnError e) {}
        dismiss_pass();
        delayed_refresh(1000, true);
    }

    private void delayed_refresh(int delay_ms, bool rescan) {
        if (DEBUG_WIFI) print("[wifi] delayed_refresh(%d ms, rescan=%s)\n", delay_ms, rescan.to_string());
        new GLib.Thread<void>("wifi-refresh-delay", () => {
            Thread.usleep((ulong) delay_ms * 1000UL);
            refresh_nets_async(rescan);
        });
    }

    private void dismiss_pass() {
        selected_row = -1;
        password_field.set_text("");
        password_field.blur();
    }

    // ─────────────────────────────────────────────────────────────────────
    // nmcli helpers
    // ─────────────────────────────────────────────────────────────────────

    private string query_connected() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device",
                out out_str, null, null);
        } catch (SpawnError e) { return ""; }

        if (DEBUG_WIFI) {
            var preview = out_str;
            if (preview.length > 300) preview = preview.substring(0, 300);
            print("[wifi] query_connected raw:\n%s\n", preview);
        }

        foreach (var line in out_str.split("\n")) {
            var p = split_nmcli_terse(line, 4);
            if (p.length >= 4 && p[1] == "wifi" && p[2] == "connected") {
                if (DEBUG_WIFI) print("[wifi] connected ssid: %s\n", p[3]);
                return p[3];
            }
        }
        if (DEBUG_WIFI) print("[wifi] connected ssid: <none>\n");
        return "";
    }

    private string get_wifi_device() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE device",
                out out_str, null, null);
        } catch (SpawnError e) { return ""; }

        foreach (var line in out_str.split("\n")) {
            var p = split_nmcli_terse(line, 3);
            if (p.length >= 3 && p[1] == "wifi") {
                return p[0];
            }
        }
        return "";
    }

    private void refresh_nets_async(bool rescan = false) {
        if (DEBUG_WIFI) print("[wifi] refresh_nets_async(rescan=%s) begin\n", rescan.to_string());
        scanning = true;
        redraw = true;

        string selected_ssid = "";
        if (selected_row >= 0 && selected_row < nets.length)
            selected_ssid = nets[selected_row].ssid;

        new GLib.Thread<void>("wifi-refresh", () => {
            if (DEBUG_WIFI) print("[wifi] refresh thread start\n");
            if (rescan) {
                try {
                    Process.spawn_command_line_async("nmcli device wifi rescan");
                    if (DEBUG_WIFI) print("[wifi] rescan requested\n");
                } catch (SpawnError e) {}
            }

            var new_nets = fetch_nets();
            var new_conn = query_connected();

            if (DEBUG_WIFI) print("[wifi] refresh result: nets=%d connected='%s'\n", new_nets.length, new_conn);

            nets = new_nets;
            connected = new_conn;
            scanning = false;

            if (selected_ssid != "") {
                int new_sel = -1;
                for (int i = 0; i < nets.length; i++) {
                    if (nets[i].ssid == selected_ssid) {
                        new_sel = i;
                        break;
                    }
                }
                selected_row = new_sel;
                if (selected_row < 0) {
                    password_field.set_text("");
                    password_field.blur();
                }
            }

            update_list_viewport_geometry();
            if (selected_row >= 0)
                list_view.ensure_visible(selected_row);

            state_changed();
            redraw = true;
            if (DEBUG_WIFI) print("[wifi] refresh apply done (selected_row=%d)\n", selected_row);
        });
    }

    private Net[] fetch_nets() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list",
                out out_str, null, null);
        } catch (SpawnError e) { return {}; }

        if (DEBUG_WIFI) {
            var preview = out_str;
            if (preview.length > 500) preview = preview.substring(0, 500);
            print("[wifi] fetch_nets raw preview:\n%s\n", preview);
        }

        Net[] result = {};
        var seen = new GLib.HashTable<string, bool>(str_hash, str_equal);
        int bad_rows = 0;
        foreach (var line in out_str.split("\n")) {
            var p = split_nmcli_terse(line, 3);
            if (p.length < 3) {
                if (line.strip() != "") bad_rows++;
                continue;
            }
            string ssid = p[0].strip();
            if (ssid == "" || ssid == "--") continue;
            if (seen.contains(ssid)) continue;
            seen.insert(ssid, true);
            int signal = 0;
            if (!int.try_parse(p[1], out signal))
                continue;
            result += new Net(ssid, signal, p[2]);
        }
        if (DEBUG_WIFI) print("[wifi] fetch_nets parsed=%d bad_rows=%d\n", result.length, bad_rows);
        return result;
    }

    private void update_list_viewport_geometry() {
        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_top     = py + HEADER_H + 6;
        int list_avail   = ph - HEADER_H - 6 - pass_reserve;
        list_view.update_layout(px + 6, list_top, pw - 12, list_avail, ROW_H, nets.length);
    }

    /**
     * Split nmcli terse output fields using ':' separator with support for
     * escaped separators (\:) and escaped backslashes (\\).
     */
    private string[] split_nmcli_terse(string line, int max_fields = -1) {
        string[] parts = {};
        var sb = new GLib.StringBuilder();
        bool escaped = false;
        int split_count = 0;

        for (int i = 0; i < line.length; i++) {
            char c = line[i];

            if (escaped) {
                sb.append_c(c);
                escaped = false;
                continue;
            }

            if (c == '\\') {
                escaped = true;
                continue;
            }

            if (c == ':' && (max_fields < 0 || split_count < max_fields - 1)) {
                parts += sb.str;
                sb.truncate(0);
                split_count++;
                continue;
            }

            sb.append_c(c);
        }

        if (escaped)
            sb.append_c('\\');

        parts += sb.str;
        return parts;
    }
}
