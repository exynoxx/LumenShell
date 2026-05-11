using DrawKit;
using GLib;

/**
 * WifiPage — full-panel WiFi manager.
 *
 * Header: title + connection chip.
 * Body: scrollable network list (WifiRow per entry).
 * Footer: password field + connect/disconnect button when a row is selected.
 */
public class WifiPage : GLib.Object, ITrayPage {

    public WifiService service { get; private set; }

    // ── Layout constants ──────────────────────────────────────────────────
    private const int PAD      = 14;
    private const int HEADER_H = 44;
    private const int ROW_H    = 36;
    private const int PASS_H   = 54;

    // ── State ─────────────────────────────────────────────────────────────
    private WifiRow[] rows         = {};
    private int       hovered_row  = -1;
    private int       selected_row = -1;

    private UiScrollView  list_view      = new UiScrollView();
    private UiButton      refresh_button = new UiButton();
    private UiButton      connect_button = new UiButton();
    private UiTextField   password_field = new UiTextField();
    private UiChip        conn_chip      = new UiChip();

    private Color sep_color = Color(){r=0.22f, g=0.24f, b=0.35f, a=0.7f};

    // Bounds from last render() — used for hit-testing
    private int px;
    private int py;
    private int pw;
    private int ph;

    public WifiPage() {
        service = new WifiService();
        service.state_changed.connect(on_service_changed);

        conn_chip.text_color = Color(){r=0.52f, g=0.52f, b=0.57f, a=1f};

        refresh_button.label         = "Refresh";
        refresh_button.text_size     = 12f;
        refresh_button.normal_color  = Color(){r=0.14f, g=0.21f, b=0.40f, a=1f};
        refresh_button.hover_color   = Color(){r=0.20f, g=0.30f, b=0.56f, a=1f};
        refresh_button.pressed_color = Color(){r=0.11f, g=0.17f, b=0.32f, a=1f};
        refresh_button.clicked.connect(() => service.refresh_scan(true));

        apply_connect_button_mode(false);
        connect_button.text_size = 14f;
        connect_button.clicked.connect(() => {
            if (is_selected_connected_row()) do_disconnect();
            else                             do_connect();
        });

        password_field.placeholder = "Password…";
        password_field.changed.connect((s)        => { redraw = true; });
        password_field.submitted.connect(()       => do_connect());
        password_field.cancelled.connect(()       => { dismiss_pass(); redraw = true; });
        password_field.focus_changed.connect((f)  => { redraw = true; });

        update_connection_chip();
        service.refresh_scan(false);
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
        apply_connect_button_mode(false);

        service.refresh_scan(false);
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
        refresh_button.set_bounds(x + PAD + 58, y + (HEADER_H - refresh_h) / 2, 78, refresh_h);
        refresh_button.render(ctx);

        int chip_w = conn_chip.get_width(ctx);
        conn_chip.set_bounds(x + w - PAD - chip_w, y + (HEADER_H - 24) / 2, chip_w, 24);
        conn_chip.render(ctx);

        ctx.draw_rect(x + PAD, y + HEADER_H, w - PAD * 2, 1, sep_color);

        // ── Network list ─────────────────────────────────────────────────
        int list_top    = y + HEADER_H + 6;
        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_avail  = h - HEADER_H - 6 - pass_reserve;
        var nets = service.nets;
        list_view.update_layout(x + 6, list_top, w - 12, list_avail, ROW_H, nets.length);

        if (selected_row >= 0) list_view.ensure_visible(selected_row);

        if (service.scanning && nets.length == 0) {
            pdt_center(ctx, "Scanning for networks…", x + w / 2, list_top + (list_avail - 14) / 2, 14f, Color(){r=0.52f, g=0.54f, b=0.62f, a=1f});
        } else if (nets.length == 0) {
            pdt_center(ctx, "No networks found", x + w / 2, list_top + (list_avail - 14) / 2, 14f, Color(){r=0.45f, g=0.46f, b=0.52f, a=1f});
        } else {
            int first = list_view.first_visible_row();
            int n     = list_view.visible_rows();
            string connected = service.connected_ssid;
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

    private void render_pass(Context ctx, int x, int y, int w, int h) {
        ctx.draw_rect(x + PAD, y + 1, w - PAD * 2, 1, Color(){r=0.22f, g=0.24f, b=0.35f, a=0.5f});

        int btn_y = y + (h - 34) / 2;

        if (is_selected_connected_row()) {
            int btn_w = 120;
            pdt(ctx, "Connected", x + PAD, btn_y + (34 - 13) / 2, 13f, Color(){r=0.58f, g=0.78f, b=0.62f, a=0.95f});
            connect_button.set_bounds(x + w - PAD - btn_w, btn_y, btn_w, 34);
        } else {
            int field_w = w - PAD * 2 - 90 - 10;
            password_field.set_bounds(x + PAD, btn_y, field_w, 34);
            password_field.render(ctx);
            connect_button.set_bounds(x + w - PAD - 90, btn_y, 90, 34);
        }
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

        if (selected_row >= 0) {
            if (!is_selected_connected_row()) password_field.mouse_down(mx, my);
            connect_button.mouse_down(mx, my);
        }

        foreach (var row in rows) row.mouse_down(mx, my);

        update_list_viewport_geometry();
        int i = list_view.row_at(mx, my);
        if (i >= 0) {
            if (selected_row == i) {
                dismiss_pass();
            } else {
                select_row(i);
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
    // Selection / connection actions
    // ─────────────────────────────────────────────────────────────────────

    private bool is_selected_connected_row() {
        var nets = service.nets;
        return selected_row >= 0
            && selected_row < nets.length
            && nets[selected_row].ssid == service.connected_ssid;
    }

    private void select_row(int i) {
        selected_row = i;
        password_field.set_text("");
        if (is_selected_connected_row()) password_field.blur();
        else                             password_field.focus();
        apply_connect_button_mode(is_selected_connected_row());
        update_list_viewport_geometry();
        list_view.ensure_visible(selected_row);
    }

    private void do_connect() {
        var nets = service.nets;
        if (selected_row < 0 || selected_row >= nets.length) return;
        service.connect_to(nets[selected_row].ssid, password_field.get_text());
        dismiss_pass();
    }

    private void do_disconnect() {
        service.disconnect_active();
        dismiss_pass();
    }

    private void dismiss_pass() {
        selected_row = -1;
        password_field.set_text("");
        password_field.blur();
        apply_connect_button_mode(false);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Service callback / display helpers
    // ─────────────────────────────────────────────────────────────────────

    private void on_service_changed() {
        // Preserve selection by SSID across rescans
        string prev_ssid = "";
        var nets = service.nets;
        if (selected_row >= 0 && selected_row < nets.length)
            prev_ssid = nets[selected_row].ssid;

        rebuild_rows();
        refresh_button.label = service.scanning ? "Scanning" : "Refresh";

        if (prev_ssid != "") {
            int new_sel = -1;
            for (int i = 0; i < nets.length; i++) {
                if (nets[i].ssid == prev_ssid) { new_sel = i; break; }
            }
            if (new_sel != selected_row) {
                selected_row = new_sel;
                if (selected_row < 0) {
                    password_field.set_text("");
                    password_field.blur();
                    apply_connect_button_mode(false);
                } else {
                    apply_connect_button_mode(is_selected_connected_row());
                }
            }
        }

        update_list_viewport_geometry();
        if (selected_row >= 0) list_view.ensure_visible(selected_row);

        update_connection_chip();
        redraw = true;
    }

    private void rebuild_rows() {
        var nets = service.nets;
        if (nets.length == rows.length) {
            bool same = true;
            for (int i = 0; i < nets.length; i++) {
                if (nets[i].ssid != rows[i].ssid) { same = false; break; }
            }
            if (same) return;
        }

        foreach (var row in rows) row.cancel_press();
        rows = {};
        foreach (var net in nets) {
            var row = new WifiRow();
            row.disconnect_clicked.connect(() => do_disconnect());
            rows += row;
        }
    }

    private void update_connection_chip() {
        string ssid   = service.connected_ssid;
        bool   online = ssid != "" && ssid != "--";
        conn_chip.set_text(online ? "●  " + ssid : "●  Offline");
        conn_chip.text_color = online
            ? Color(){r=0.18f, g=0.88f, b=0.42f, a=1f}
            : Color(){r=0.52f, g=0.52f, b=0.57f, a=1f};
    }

    private void apply_connect_button_mode(bool disconnect_mode) {
        if (disconnect_mode) {
            connect_button.label         = "Disconnect";
            connect_button.normal_color  = Color(){r=0.76f, g=0.20f, b=0.20f, a=1f};
            connect_button.hover_color   = Color(){r=0.88f, g=0.26f, b=0.26f, a=1f};
            connect_button.pressed_color = Color(){r=0.64f, g=0.16f, b=0.16f, a=1f};
        } else {
            connect_button.label         = "Connect";
            connect_button.normal_color  = Color(){r=0.12f, g=0.34f, b=0.88f, a=1f};
            connect_button.hover_color   = Color(){r=0.20f, g=0.50f, b=1.0f,  a=1f};
            connect_button.pressed_color = Color(){r=0.10f, g=0.28f, b=0.72f, a=1f};
        }
    }

    private void update_list_viewport_geometry() {
        int pass_reserve = (selected_row >= 0) ? PASS_H : 0;
        int list_top     = py + HEADER_H + 6;
        int list_avail   = ph - HEADER_H - 6 - pass_reserve;
        list_view.update_layout(px + 6, list_top, pw - 12, list_avail, ROW_H, service.nets.length);
    }
}
