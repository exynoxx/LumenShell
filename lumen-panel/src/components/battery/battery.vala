using DrawKit;

/**
 * BatteryTray — icon that lives in the tray bar.
 *
 * Owns the shared BatteryService and hands it to BatteryPage.
 */
public class BatteryTray : IconAndText, IUpdateable, IHasPage {

    private BatteryService _service;
    private BatteryPage    _page;
    public  string         status = "";

    public BatteryTray() {
        base(new HoverableIcon("nobattery"));
        _service = new BatteryService();
        _page    = new BatteryPage(_service);
        _service.state_changed.connect(() => {
            update();
            redraw = true;
        });
        update();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()                   { return _page; }
    public bool      is_icon_hovered()            { return icon.hovered; }
    public void      set_page_active(bool active) { icon.selected = active; }

    // ── IUpdateable ───────────────────────────────────────────────────────

    public string get_status() { return status; }

    public void update() {
        var raw      = _service.raw_status;
        var new_icon = "nobattery";

        if (raw == "discharging" || raw.contains("full")) {
            if (_service.charge_full > 0) {
                var pct = _service.percent;
                status   = "%d%%".printf(pct);
                new_icon = pct >= 70 ? "high" : pct >= 30 ? "mid" : "low";
            }
        } else if (raw == "charging") {
            new_icon = "charging";
            if (_service.charge_full > 0)
                status = "%d%% ⚡".printf(_service.percent);
        } else {
            status = "N/A";
        }

        icon.set_icon(new_icon);
    }
}
