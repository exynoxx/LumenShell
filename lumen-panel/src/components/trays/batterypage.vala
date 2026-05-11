using DrawKit;
using GLib;

/**
 * BatteryPage — full-panel battery information display.
 *
 * Exposes a shared BatteryService so BatteryTray can subscribe to the
 * same data without independent sysfs reads.
 */
public class BatteryPage : BaseTrayPage {

    public BatteryService service { get; private set; }

    private const int PAD   = 16;
    private const int BAR_H = 22;

    private UiProgressBar progress = new UiProgressBar();

    // Cached display values — updated in refresh() whenever service fires
    private string cached_pct_str     = "0%";
    private Color  cached_pct_col;
    private string cached_voltage_str = "";
    private string cached_current_str = "";
    private string cached_charge_str  = "";
    private string cached_time_str    = "";
    private bool   cached_has_time    = false;
    private string cached_status_str  = "—";
    private int    cached_pct_w       = -1;  // text-width cache, -1 = dirty

    public BatteryPage() {
        service = new BatteryService();
        progress.track_color = Color(){r=0.10f, g=0.11f, b=0.16f, a=1f};

        service.state_changed.connect(() => {
            refresh();
            redraw = true;
        });

        service.refresh();
    }

    public override string get_title() { return "Battery"; }

    public override void on_activate() { service.refresh(); }

    public override void render(Context ctx, int x, int y, int w, int h) {
        int cx  = x + w / 2;
        int cur = y + PAD;

        pdt(ctx, "Battery", x + PAD, cur, 16f, Color(){r=0.62f, g=0.64f, b=0.72f, a=1f});
        cur += 26;

        pdt_center(ctx, cached_pct_str, cx, cur, 40f, cached_pct_col);
        cur += 50;

        pdt_center(ctx, cached_status_str, cx, cur, 14f, Color(){r=0.60f, g=0.62f, b=0.70f, a=1f});
        cur += 24;

        int bar_x = x + PAD;
        int bar_w = w - PAD * 2;
        progress.set_bounds(bar_x, cur, bar_w, BAR_H);
        progress.render(ctx);

        if (cached_pct_w < 0) cached_pct_w = ctx.width_of(cached_pct_str, 11f);
        int blx = bar_x + bar_w - cached_pct_w - 8;
        pdt(ctx, cached_pct_str, blx, cur + (BAR_H - 11) / 2, 11f, Color(){r=1f, g=1f, b=1f, a=0.65f});
        cur += BAR_H + 14;

        int col1 = x + PAD;
        int col2 = x + w / 2;
        render_stat(ctx, col1, cur, "Voltage", cached_voltage_str);
        render_stat(ctx, col2, cur, "Current", cached_current_str);
        cur += 32;
        render_stat(ctx, col1, cur, "Charge", cached_charge_str);
        if (cached_has_time)
            render_stat(ctx, col2, cur, "Est. time", cached_time_str);
    }

    private void render_stat(Context ctx, int x, int y, string label, string value) {
        pdt(ctx, label, x, y,      11f,   Color(){r=0.42f, g=0.44f, b=0.52f, a=1f});
        pdt(ctx, value, x, y + 14, 13.5f, Color(){r=0.84f, g=0.86f, b=0.92f, a=1f});
    }

    private void refresh() {
        var svc       = service;
        var raw       = svc.raw_status;
        var percent   = svc.percent;

        if (raw == "charging")
            cached_status_str = "⚡ Charging";
        else if (raw == "discharging")
            cached_status_str = "Discharging";
        else if (raw.contains("full"))
            cached_status_str = "✓ Full";
        else
            cached_status_str = raw.length > 0 ? raw : "Unknown";

        cached_pct_str = "%d%%".printf(percent);
        cached_pct_w   = -1;  // invalidate text-width cache

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

        cached_voltage_str = "%.2f V".printf(svc.voltage_v);
        cached_current_str = "%.2f A".printf(svc.current_a);
        cached_charge_str  = "%d / %d mAh".printf(svc.charge_now / 1000, svc.charge_full / 1000);

        cached_has_time = false;
        if (raw == "discharging" && svc.current_a > 0.05f) {
            float hrs   = (svc.charge_now / 1000000f) / svc.current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            cached_time_str = h_rem > 0
                ? "%dh %dm left".printf(h_rem, m_rem)
                : "%dm left".printf(m_rem);
            cached_has_time = true;
        } else if (raw == "charging" && svc.current_a > 0.05f) {
            float hrs   = ((svc.charge_full - svc.charge_now) / 1000000f) / svc.current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            cached_time_str = h_rem > 0
                ? "%dh %dm to full".printf(h_rem, m_rem)
                : "%dm to full".printf(m_rem);
            cached_has_time = true;
        }
    }
}
