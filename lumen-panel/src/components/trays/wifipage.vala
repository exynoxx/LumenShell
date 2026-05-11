using DrawKit;
using GLib;

/**
 * WiFiPage — full-panel WiFi manager.
 *
 * Header: title + connection chip.
 * Body: scrollable network list (WifiRow per entry).
 * Footer: password field + connect/disconnect button when a row is selected.
 */
public class WifiPage : GLib.Object, ITrayPage {

    public signal void state_changed();

    // ── Layout constants ──────────────────────────────────────────────────
    private const int PAD      = 14;
    private const int HEADER_H = 44;
    private const int ROW_H    = 36;
    private const int PASS_H   = 54;

    // ── State ─────────────────────────────────────────────────────────────
    private NmcliClient nmcli        = new NmcliClient();
    private WifiNet[]   nets         = {};
    private WifiRow[]   rows         = {};
    private string      connected    = "";
    private int         hovered_row  = -1;
    private int         selected_row = -1;
    private bool        scanning     = false;

    // Pre-fetch state — background thread writes at startup, on_activate() consumes
    private GLib.Mutex pre_mutex;
    private WifiNet[]  pre_nets  = {};
    private string     pre_conn  = "";
    private bool       pre_ready = false;

    private UiScrollView  list_view         = new UiScrollView();
    private UiButton      refresh_button    = new UiButton();
    private UiButton      connect_button    = new UiButton();
    private UiTextField   password_field    = new UiTextField();

    // Tracks current connect-button mode to avoid per-frame color reassignment
    private bool connect_btn_is_disconnect = false;

    // Connection-chip composite — text updated in update_connection_chip()
    private UiChip conn_chip = new UiChip();

    // Cached separator color
    private Color sep_color = Color(){r=0.22f, g=0.24f, b=0.35f, a=0.7f};

    // Bounds from last render() call — used for hit-testing
    private int px;
    private int py;
    private int pw;
    private int ph;

    public WifiPage() {
        conn_chip.text_color = Color(){r=0.52f, g=0.52f, b=0.57f, a=1f};

        refresh_button.label         = "Refresh";
        refresh_button.text_size     = 12f;
        refresh_button.normal_color  = Color(){r=0.14f, g=0.21f, b=0.40f, a=1f};
        refresh_button.hover_color   = Color(){r=0.20f, g=0.30f, b=0.56f, a=1f};
        refresh_button.pressed_color = Color(){r=0.11f, g=0.17f, b=0.32f, a=1f};
        refresh_button.clicked.connect(() => {
            refresh_nets_async(true);
            redraw = true;
        });

        connect_button.label         = "Connect";
        connect_button.text_size     = 14f;
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

        password_field.placeholder = "Password…";
        password_field.changed.connect((s) => { redraw = true; });
        password_field.submitted.connect(() => { do_connect(); });
        password_field.cancelled.connect(() => { dismiss_pass(); redraw = true; });
        password_field.focus_changed.connect((focused) => { redraw = true; });

        update_connection_chip();

        new GLib.Thread<void>("wifi-prefetch", () => {
            var new_nets = nmcli.fetch_nets();
            var new_conn = nmcli.query_connected();
            pre_mutex.lock();
            pre_nets  = new_nets;
            pre_conn  = new_conn;
            pre_ready = true;
            pre_mutex.unlock();
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    // ITrayPage
    // ─────────────────────────────────────────────────────────────────────

    public string get_title() { return "WiFi"; }

    public void on_activate() {
        selected_row = -1;
        hovered_row  = -1;
        list_view.reset();
        password_field.set_text("");
        password_field.blur();
        connect_button.cancel_press();

        // Seed the list from the startup pre-fetch if we have nothing to show yet
        if (nets.length == 0) {
            pre_mutex.lock();
            bool      has_pre   = pre_ready;
            WifiNet[] init_nets = pre_nets;
            string    init_conn = pre_conn;
            pre_mutex.unlock();

            if (has_pre) {
                nets      = init_nets;
                connected = init_conn;
                rebuild_rows();
            }
        }

        pre_mutex.lock();
        pre_ready = false;
        pre_mutex.unlock();

        update_connection_chip();
        refresh_nets_async(false);
    }

    public void on_deactivate() {
        dismiss_pass();
    }

    public void mouse_up(int mx, int my) {
        refresh_button.mouse_up(mx, my);
        connect_button.mouse_up(mx, my);
        foreach (var row in rows) row.mouse_up(mx, my);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    public void render(Context ctx, int x, int y, int w, int h) {
        px = x;  py = y;  pw = w;  ph = h;

        // ── Header ───────────────────────────────────────────────────────
        int title_top = y + (HEADER_H - 20) / 2;
        pdt(ctx, "WiFi", x + PAD, title_top, 20f, {1f, 1f, 1f, 1f});

        int refresh_h = 24;
        int refresh_x = x + PAD + 58;
        int refresh_y = y + (HEADER_H - refresh_h) / 2;
        refresh_button.set_bounds(refresh_x, refresh_y, 78, refresh_h);
        refresh_button.render(ctx);

        // Connection chip (right-aligned)
        int chip_w = conn_chip.get_width(ctx);
        int chip_x = x + w - PAD - chip_w;
        int chip_y = y + (HEADER_H - 24) / 2;
        conn_chip.set_bounds(chip_x, chip_y, chip_w, 24);
        conn_chip.render(ctx);

        // Separator
        ctx.draw_rect(x + PAD, y + HEADER_H, w - PAD * 2, 1, sep_color);

        // ── Network list ─────────────────────────────────────────────────
        int list_top    = y + HEADER_H + 6;
        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_avail  = h - HEADER_H - 6 - pass_reserve;
        list_view.update_layout(x + 6, list_top, w - 12, list_avail, ROW_H, nets.length);

        if (selected_row >= 0) list_view.ensure_visible(selected_row);

        if (scanning && nets.length == 0) {
            pdt_center(ctx, "Scanning for networks…", x + w / 2, list_top + (list_avail - 14) / 2, 14f, Color(){r=0.52f, g=0.54f, b=0.62f, a=1f});
        } else if (nets.length == 0) {
            pdt_center(ctx, "No networks found", x + w / 2, list_top + (list_avail - 14) / 2, 14f, Color(){r=0.45f, g=0.46f, b=0.52f, a=1f});
        } else {
            int first = list_view.first_visible_row();
            int n     = list_view.visible_rows();
            for (int rel = 0; rel < n; rel++) {
                int i = first + rel;
                if (i >= nets.length || i >= rows.length) break;
                rows[i].ssid         = nets[i].ssid;
                rows[i].signal_val   = nets[i].signal;
                rows[i].security     = nets[i].security;
                rows[i].is_connected = (nets[i].ssid == connected);
                rows[i].hovered      = (hovered_row == i);
                rows[i].selected     = (selected_row == i);
                rows[i].set_bounds(x, list_top + rel * ROW_H, w, ROW_H);
                rows[i].render(ctx);
            }
            list_view.render(ctx);
        }

        // ── Password area ─────────────────────────────────────────────────
        if (selected_row >= 0 && selected_row < nets.length)
            render_pass(ctx, x, y + h - PASS_H, w, PASS_H);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Password area
    // ─────────────────────────────────────────────────────────────────────

    private void render_pass(Context ctx, int x, int y, int w, int h) {
        ctx.draw_rect(x + PAD, y + 1, w - PAD * 2, 1, Color(){r=0.22f, g=0.24f, b=0.35f, a=0.5f});

        bool is_conn_row = selected_row >= 0
                        && selected_row < nets.length
                        && nets[selected_row].ssid == connected;

        if (is_conn_row) {
            int btn_w = 120;
            int btn_x = x + w - PAD - btn_w;
            int btn_y = y + (h - 34) / 2;

            pdt(ctx, "Connected", x + PAD, btn_y + (34 - 13) / 2, 13f, Color(){r=0.58f, g=0.78f, b=0.62f, a=0.95f});

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
        connect_button.set_bounds(x + w - PAD - 90, field_y, 90, 34);
        connect_button.render(ctx);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Mouse handling
    // ─────────────────────────────────────────────────────────────────────

    public void mouse_motion(int mx, int my) {
        refresh_button.mouse_motion(mx, my);
        connect_button.mouse_motion(mx, my);
        password_field.mouse_motion(mx, my);
        foreach (var row in rows) row.mouse_motion(mx, my);

        update_list_viewport_geometry();
        hovered_row = list_view.row_at(mx, my);
    }

    public void mouse_down(int mx, int my) {
        refresh_button.mouse_down(mx, my);

        if (selected_row >= 0 && selected_row < nets.length) {
            bool is_conn_row = nets[selected_row].ssid == connected;
            if (!is_conn_row) password_field.mouse_down(mx, my);
            connect_button.mouse_down(mx, my);
        }

        foreach (var row in rows) row.mouse_down(mx, my);

        update_list_viewport_geometry();
        int i = list_view.row_at(mx, my);
        if (i >= 0) {
            if (selected_row == i) {
                dismiss_pass();
            } else {
                selected_row = i;
                password_field.set_text("");
                if (i < nets.length && nets[i].ssid == connected)
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
        try { Process.spawn_command_line_async(cmd); } catch (SpawnError e) {}
        dismiss_pass();
        delayed_refresh(1400, true);
    }

    private void do_disconnect() {
        string dev = nmcli.get_wifi_device();
        if (dev == "") return;
        string cmd = @"nmcli device disconnect \"$dev\"";
        try { Process.spawn_command_line_async(cmd); } catch (SpawnError e) {}
        dismiss_pass();
        delayed_refresh(1000, true);
    }

    private void delayed_refresh(int delay_ms, bool rescan) {
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
    // Display helpers
    // ─────────────────────────────────────────────────────────────────────

    private void update_connection_chip() {
        bool is_conn = connected != "" && connected != "--";
        conn_chip.set_text(is_conn ? "●  " + connected : "●  Offline");
        conn_chip.text_color = is_conn
            ? Color(){r=0.18f, g=0.88f, b=0.42f, a=1f}
            : Color(){r=0.52f, g=0.52f, b=0.57f, a=1f};
    }

    // ─────────────────────────────────────────────────────────────────────
    // Background refresh (thread-safe via GLib.Idle)
    // ─────────────────────────────────────────────────────────────────────

    private void refresh_nets_async(bool rescan = false) {
        // Only blank the list if the user explicitly rescanned or there's nothing to show yet
        if (rescan || nets.length == 0) {
            nets             = {};
            rows             = {};
            scanning         = true;
            refresh_button.label = "Scanning";
            redraw           = true;
        }

        string selected_ssid = "";
        if (selected_row >= 0 && selected_row < nets.length)
            selected_ssid = nets[selected_row].ssid;

        new GLib.Thread<void>("wifi-refresh", () => {
            if (rescan) {
                try { Process.spawn_command_line_async("nmcli device wifi rescan"); } catch (SpawnError e) {}
            }

            var new_nets = nmcli.fetch_nets();
            var new_conn = nmcli.query_connected();

            // Apply results on the main thread
            GLib.Idle.add(() => {
                nets      = new_nets;
                connected = new_conn;
                scanning  = false;
                refresh_button.label = "Refresh";
                update_connection_chip();
                rebuild_rows();

                if (selected_ssid != "") {
                    int new_sel = -1;
                    for (int i = 0; i < nets.length; i++) {
                        if (nets[i].ssid == selected_ssid) { new_sel = i; break; }
                    }
                    selected_row = new_sel;
                    if (selected_row < 0) {
                        password_field.set_text("");
                        password_field.blur();
                    }
                }

                update_list_viewport_geometry();
                if (selected_row >= 0) list_view.ensure_visible(selected_row);

                state_changed();
                redraw = true;
                return Source.REMOVE;
            });
        });
    }

    private void rebuild_rows() {
        foreach (var row in rows) row.cancel_press();
        rows = {};
        foreach (var net in nets) {
            var row = new WifiRow();
            row.disconnect_clicked.connect(() => do_disconnect());
            rows += row;
        }
    }

    private void update_list_viewport_geometry() {
        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_top     = py + HEADER_H + 6;
        int list_avail   = ph - HEADER_H - 6 - pass_reserve;
        list_view.update_layout(px + 6, list_top, pw - 12, list_avail, ROW_H, nets.length);
    }
}
