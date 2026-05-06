using DrawKit;
using GLib;

/**
 * BatteryPage — full-panel battery information display.
 *
 * Shows:
 *   • Large percentage number with colour-coded charge level
 *   • Status label (Charging ⚡ / Discharging / Full ✓)
 *   • Wide charge bar with colour-coded fill
 *   • Stats grid: Voltage · Current · Remaining charge · Time estimate
 */
public class BatteryPage : BaseTrayPage {

    private const int PAD = 16;
    private UiProgressBar progress = new UiProgressBar();

    private const int BAR_H = 22;

    // Cached display values — updated in refresh() on each state change
    private string cached_pct_str     = "0%";
    private Color  cached_pct_col;
    private string cached_voltage_str = "";
    private string cached_current_str = "";
    private string cached_charge_str  = "";
    private string cached_time_str    = "";
    private bool   cached_has_time    = false;

    public BatteryPage() {
        progress.track_color = Color(){r=0.10f, g=0.11f, b=0.16f, a=1f};
    }

    // ── Cached sysfs data ─────────────────────────────────────────────────
    private int    percent      = 0;
    private string status_str   = "—";
    private string raw_status   = "";
    private float  voltage_v    = 0f;
    private float  current_a    = 0f;
    private int    charge_full  = 0;    // µAh
    private int    charge_now   = 0;    // µAh

    // ─────────────────────────────────────────────────────────────────────
    // ITrayPage
    // ─────────────────────────────────────────────────────────────────────

    public override string get_title() { return "Battery"; }

    public override void on_activate() { refresh(); }

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    public override void render(Context ctx, int x, int y, int w, int h) {
        int cx  = x + w / 2;
        int cur = y + PAD;

        // ── Title ─────────────────────────────────────────────────────────
        pdt(ctx, "Battery", x + PAD, cur, 16f,
            Color(){r=0.62f, g=0.64f, b=0.72f, a=1f});
        cur += 26;

        // ── Large percentage ──────────────────────────────────────────────
        pdt_center(ctx, cached_pct_str, cx, cur, 40f, cached_pct_col);
        cur += 50;

        // ── Status ────────────────────────────────────────────────────────
        pdt_center(ctx, status_str, cx, cur, 14f,
            Color(){r=0.60f, g=0.62f, b=0.70f, a=1f});
        cur += 24;

        // ── Charge bar ────────────────────────────────────────────────────
        int bar_x = x + PAD;
        int bar_w = w - PAD * 2;
        progress.set_bounds(bar_x, cur, bar_w, BAR_H);
        progress.render(ctx);

        int blx = bar_x + bar_w - ctx.width_of(cached_pct_str, 11f) - 8;
        pdt(ctx, cached_pct_str, blx, cur + (BAR_H - 11) / 2, 11f,
            Color(){r=1f, g=1f, b=1f, a=0.65f});
        cur += BAR_H + 14;

        // ── Stats grid (2 × 2) ────────────────────────────────────────────
        int col1 = x + PAD;
        int col2 = x + w / 2;
        render_stat(ctx, col1, cur, "Voltage", cached_voltage_str);
        render_stat(ctx, col2, cur, "Current", cached_current_str);
        cur += 32;
        render_stat(ctx, col1, cur, "Charge",  cached_charge_str);
        if (cached_has_time)
            render_stat(ctx, col2, cur, "Est. time", cached_time_str);
    }

    private void render_stat(Context ctx, int x, int y, string label, string value) {
        pdt(ctx, label, x, y, 11f,
            Color(){r=0.42f, g=0.44f, b=0.52f, a=1f});
        pdt(ctx, value, x, y + 14, 13.5f,
            Color(){r=0.84f, g=0.86f, b=0.92f, a=1f});
    }

    // ─────────────────────────────────────────────────────────────────────
    // sysfs helpers
    // ─────────────────────────────────────────────────────────────────────

    private void refresh() {
        raw_status  = sysfs_str("status").down().strip();
        charge_full = sysfs_int("charge_full");
        charge_now  = sysfs_int("charge_now");
        voltage_v   = sysfs_int("voltage_now") / 1000000f;
        current_a   = sysfs_int("current_now") / 1000000f;

        if (charge_full > 0)
            percent = (int)((charge_now / (float) charge_full) * 100);
        percent = int.min(100, int.max(0, percent));

        if (raw_status == "charging")
            status_str = "⚡ Charging";
        else if (raw_status == "discharging")
            status_str = "Discharging";
        else if (raw_status.contains("full"))
            status_str = "✓ Full";
        else
            status_str = raw_status.length > 0 ? raw_status : "Unknown";

        // ── Cache display values so render() stays pure draw calls ───────────
        cached_pct_str = "%d%%".printf(percent);
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

        cached_voltage_str = "%.2f V".printf(voltage_v);
        cached_current_str = "%.2f A".printf(current_a);
        cached_charge_str  = "%d / %d mAh".printf(charge_now / 1000, charge_full / 1000);

        cached_has_time = false;
        if (raw_status == "discharging" && current_a > 0.05f) {
            float hrs   = (charge_now / 1000000f) / current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            cached_time_str = h_rem > 0
                ? "%dh %dm left".printf(h_rem, m_rem)
                : "%dm left".printf(m_rem);
            cached_has_time = true;
        } else if (raw_status == "charging" && current_a > 0.05f) {
            float hrs   = ((charge_full - charge_now) / 1000000f) / current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            cached_time_str = h_rem > 0
                ? "%dh %dm to full".printf(h_rem, m_rem)
                : "%dm to full".printf(m_rem);
            cached_has_time = true;
        }
    }

    private static string sysfs_str(string name) {
        string out_str, err;
        try {
            int exit;
            Process.spawn_command_line_sync(
                "cat /sys/class/power_supply/BAT0/" + name,
                out out_str, out err, out exit);
            return exit == 0 ? out_str.strip() : "";
        } catch (Error e) { return ""; }
    }

    private static int sysfs_int(string name) {
        return int.parse(sysfs_str(name));
    }
}
