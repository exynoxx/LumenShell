using DrawKit;

/**
 * BatteryTray — icon that lives in the tray bar.
 *
 * Displays the appropriate battery icon tinted to charge level.
 * Clicking it tells the Tray to open/close the BatteryPage expansion.
 * All detailed rendering has moved to BatteryPage.
 */
public class BatteryTray : IconAndText, IUpdateable, IHasPage {

    private BatteryPage _page;
    public  string status = "";

    public BatteryTray(Context ctx) {
        base(ctx, new HoverableIcon("nobattery"), "N/A");
        _page = new BatteryPage();
        update();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()        { return _page; }
    public bool      is_icon_hovered() { return icon.hovered; }
    public void      set_page_active(bool active) { icon.selected = active; }

    // ── IUpdateable ───────────────────────────────────────────────────────

    public string get_status() { return status; }

    public void update() {
        var raw = sysfs("status").down().strip();
        var new_icon = "nobattery";

        if (raw == "discharging" || raw.contains("full")) {
            var full = sysfs_int("charge_full");
            var curr = sysfs_int("charge_now");
            if (full > 0) {
                var pct = (int)((curr / (float) full) * 100);
                pct    = int.min(100, int.max(0, pct));
                status = "%d%%".printf(pct);
                new_icon = pct >= 70 ? "high" : pct >= 30 ? "mid" : "low";
                set_text(status);
            }
        } else if (raw == "charging") {
            new_icon = "charging";
            var full = sysfs_int("charge_full");
            var curr = sysfs_int("charge_now");
            if (full > 0) {
                var pct = (int)((curr / (float) full) * 100);
                pct    = int.min(100, int.max(0, pct));
                status = "%d%% ⚡".printf(pct);
                set_text(status);
            }
        } else {
            set_text("N/A");
            return;
        }

        icon.set_icon(new_icon);
    }

    private static string sysfs(string name) {
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
        return int.parse(sysfs(name));
    }
}
