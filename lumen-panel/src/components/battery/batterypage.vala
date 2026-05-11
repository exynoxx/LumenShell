using DrawKit;
using GLib;

/**
 * BatteryPage — full-panel battery information display.
 *
 * BatteryService is injected so the tray and page see the same readings.
 */
public class BatteryPage : BaseTrayPage {

    private BatteryService service;

    // ── Layout constants ──────────────────────────────────────────────────
    private const int PAD       = 16;
    private const int BAR_H     = 22;
    private const int DY_TITLE  = PAD;                       // 16
    private const int DY_PCT    = DY_TITLE  + 26;            // 42
    private const int DY_STATUS = DY_PCT    + 50;            // 92
    private const int DY_BAR    = DY_STATUS + 24;            // 116
    private const int DY_STAT1  = DY_BAR    + BAR_H + 14;    // 152
    private const int DY_STAT2  = DY_STAT1  + 32;            // 184

    // ── Cached colours ────────────────────────────────────────────────────
    private Color title_col      = Color(){r=0.62f, g=0.64f, b=0.72f, a=1f};
    private Color status_col     = Color(){r=0.60f, g=0.62f, b=0.70f, a=1f};
    private Color stat_label_col = Color(){r=0.42f, g=0.44f, b=0.52f, a=1f};
    private Color stat_value_col = Color(){r=0.84f, g=0.86f, b=0.92f, a=1f};
    private Color bar_text_col   = Color(){r=1f,    g=1f,    b=1f,    a=0.65f};
    private Color track_col      = Color(){r=0.10f, g=0.11f, b=0.16f, a=1f};

    private UiProgressBar progress = new UiProgressBar();

    // ── Layout — derived from bounds, locked once ─────────────────────────
    private int bar_dx = 0;    // bar x relative to page x
    private int bar_w  = 0;
    private int col1_dx = 0;   // first stat column relative to page x
    private int col2_dx = 0;   // second stat column relative to page x

    // ── Cached display values — updated in refresh() ──────────────────────
    private string cached_pct_str     = "0%";
    private Color  cached_pct_col;
    private string cached_voltage_str = "";
    private string cached_current_str = "";
    private string cached_charge_str  = "";
    private string cached_time_str    = "";
    private bool   cached_has_time    = false;
    private string cached_status_str  = "—";
    private int    cached_pct_w       = -1;  // text-width cache, -1 = dirty

    public BatteryPage(BatteryService service) {
        this.service = service;
        progress.track_color = track_col;
        service.state_changed.connect(() => {
            refresh();
            redraw = true;
        });
        service.refresh();
    }

    protected override void on_bounds_set() {
        bar_dx  = PAD;
        bar_w   = bounds_w - PAD * 2;
        col1_dx = PAD;
        col2_dx = bounds_w / 2;
    }

    public override string get_title() { return "Battery"; }

    public override void on_activate() { service.refresh(); }

    protected override void render_content(Context ctx, int x, int y) {
        int cx = x + bounds_w / 2;

        pdt(ctx,        "Battery",          x + PAD, y + DY_TITLE,  16f, title_col);
        pdt_center(ctx, cached_pct_str,     cx,      y + DY_PCT,    40f, cached_pct_col);
        pdt_center(ctx, cached_status_str,  cx,      y + DY_STATUS, 14f, status_col);

        progress.set_bounds(x + bar_dx, y + DY_BAR, bar_w, BAR_H);
        progress.render(ctx);

        if (cached_pct_w < 0) cached_pct_w = ctx.width_of(cached_pct_str, 11f);
        int pct_label_x = x + bar_dx + bar_w - cached_pct_w - 8;
        pdt(ctx, cached_pct_str, pct_label_x, y + DY_BAR + (BAR_H - 11) / 2, 11f, bar_text_col);

        render_stat(ctx, x + col1_dx, y + DY_STAT1, "Voltage", cached_voltage_str);
        render_stat(ctx, x + col2_dx, y + DY_STAT1, "Current", cached_current_str);
        render_stat(ctx, x + col1_dx, y + DY_STAT2, "Charge",  cached_charge_str);
        if (cached_has_time)
            render_stat(ctx, x + col2_dx, y + DY_STAT2, "Est. time", cached_time_str);
    }

    private void render_stat(Context ctx, int x, int y, string label, string value) {
        pdt(ctx, label, x, y,      11f,   stat_label_col);
        pdt(ctx, value, x, y + 14, 13.5f, stat_value_col);
    }

    private void refresh() {
        var raw     = service.raw_status;
        var percent = service.percent;

        if (raw == "charging")          cached_status_str = "⚡ Charging";
        else if (raw == "discharging")  cached_status_str = "Discharging";
        else if (raw.contains("full"))  cached_status_str = "✓ Full";
        else                            cached_status_str = raw.length > 0 ? raw : "Unknown";

        cached_pct_str = "%d%%".printf(percent);
        cached_pct_w   = -1;

        cached_pct_col = percent >= 60
            ? Color(){r=0.18f, g=0.88f, b=0.42f, a=1f}
            : percent >= 25
                ? Color(){r=1.0f, g=0.74f, b=0.14f, a=1f}
                : Color(){r=1.0f, g=0.28f, b=0.28f, a=1f};

        progress.set_value(percent);
        progress.fill_color = percent >= 60
            ? Color(){r=0.13f, g=0.76f, b=0.34f, a=1f}
            : percent >= 25
                ? Color(){r=0.90f, g=0.62f, b=0.06f, a=1f}
                : Color(){r=0.86f, g=0.20f, b=0.20f, a=1f};

        cached_voltage_str = "%.2f V".printf(service.voltage_v);
        cached_current_str = "%.2f A".printf(service.current_a);
        cached_charge_str  = "%d / %d mAh".printf(service.charge_now / 1000, service.charge_full / 1000);

        cached_has_time = false;
        if (raw == "discharging" && service.current_a > 0.05f) {
            float hrs   = (service.charge_now / 1000000f) / service.current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            cached_time_str = h_rem > 0
                ? "%dh %dm left".printf(h_rem, m_rem)
                : "%dm left".printf(m_rem);
            cached_has_time = true;
        } else if (raw == "charging" && service.current_a > 0.05f) {
            float hrs   = ((service.charge_full - service.charge_now) / 1000000f) / service.current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            cached_time_str = h_rem > 0
                ? "%dh %dm to full".printf(h_rem, m_rem)
                : "%dm to full".printf(m_rem);
            cached_has_time = true;
        }
    }
}
