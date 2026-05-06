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
public class BatteryPage : GLib.Object, ITrayPage {

    private const int PAD = 16;
    private UiProgressBar progress = new UiProgressBar();

    // Tracks last rendered charge tier (0=low, 1=mid, 2=ok) to avoid per-frame color writes
    private int progress_tier = -1;

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

    public string get_title() { return "Battery"; }

    public void on_activate()   { refresh(); }
    public void on_deactivate() {}

    public void mouse_down(int mx, int my) {}
    public void mouse_up  (int mx, int my) {}
    public void mouse_motion(int mx, int my) {}
    public void mouse_scroll(int mx, int my, int amount) {}

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    public void render(Context ctx, int x, int y, int w, int h) {
        int cx  = x + w / 2;
        int cur = y + PAD;

        // ── Title ─────────────────────────────────────────────────────────
        pdt(ctx, "Battery", x + PAD, cur, 16f,
            Color(){r=0.62f, g=0.64f, b=0.72f, a=1f});
        cur += 26;

        // ── Large percentage ──────────────────────────────────────────────
        string pct_str = "%d%%".printf(percent);
        Color  pct_col = percent >= 60
            ? Color(){r=0.18f, g=0.88f, b=0.42f, a=1f}
            : percent >= 25
                ? Color(){r=1.0f,  g=0.74f, b=0.14f, a=1f}
                : Color(){r=1.0f,  g=0.28f, b=0.28f, a=1f};
        pdt_center(ctx, pct_str, cx, cur, 40f, pct_col);
        cur += 50;

        // ── Status ────────────────────────────────────────────────────────
        pdt_center(ctx, status_str, cx, cur, 14f,
            Color(){r=0.60f, g=0.62f, b=0.70f, a=1f});
        cur += 24;

        // ── Charge bar ────────────────────────────────────────────────────
        int bar_x = x + PAD;
        int bar_w = w - PAD * 2;
        int bar_h = 22;

        progress.set_bounds(bar_x, cur, bar_w, bar_h);
        progress.set_value(percent);
        int tier = percent >= 60 ? 2 : percent >= 25 ? 1 : 0;
        if (tier != progress_tier) {
            progress_tier = tier;
            progress.fill_color = tier == 2
                ? Color(){r=0.13f, g=0.76f, b=0.34f, a=1f}
                : tier == 1
                    ? Color(){r=0.90f, g=0.62f, b=0.06f, a=1f}
                    : Color(){r=0.86f, g=0.20f, b=0.20f, a=1f};
        }
        progress.render(ctx);

        // Percentage label inside bar (right-aligned)
        string bar_label = "%d%%".printf(percent);
        int blx = bar_x + bar_w - ctx.width_of(bar_label, 11f) - 8;
        pdt(ctx, bar_label, blx, cur + (bar_h - 11) / 2, 11f,
            Color(){r=1f, g=1f, b=1f, a=0.65f});

        cur += bar_h + 14;

        // ── Stats grid (2 × 2) ────────────────────────────────────────────
        int col1 = x + PAD;
        int col2 = x + w / 2;

        render_stat(ctx, col1, cur,
            "Voltage",  "%.2f V".printf(voltage_v));
        render_stat(ctx, col2, cur,
            "Current",  "%.2f A".printf(current_a));
        cur += 32;

        render_stat(ctx, col1, cur,
            "Charge",   "%d / %d mAh".printf(
                charge_now / 1000, charge_full / 1000));

        // Estimated time
        if (raw_status == "discharging" && current_a > 0.05f) {
            float hrs   = (charge_now / 1000000f) / current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            string t    = h_rem > 0
                ? "%dh %dm left".printf(h_rem, m_rem)
                : "%dm left".printf(m_rem);
            render_stat(ctx, col2, cur, "Est. time", t);
        } else if (raw_status == "charging" && current_a > 0.05f) {
            float hrs   = ((charge_full - charge_now) / 1000000f) / current_a;
            int   h_rem = (int) hrs;
            int   m_rem = (int)((hrs - h_rem) * 60);
            string t    = h_rem > 0
                ? "%dh %dm to full".printf(h_rem, m_rem)
                : "%dm to full".printf(m_rem);
            render_stat(ctx, col2, cur, "Est. time", t);
        }
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
