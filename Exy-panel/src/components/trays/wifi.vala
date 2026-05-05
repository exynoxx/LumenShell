using DrawKit;
using GLib;

/**
 * WifiTray — icon that lives in the tray bar.
 *
 * Displays a WiFi icon (tinted green when connected, grey when offline).
 * Clicking it tells the Tray to open/close the WifiPage expansion.
 * All panel rendering has moved to WifiPage.
 */
public class WifiTray : IconAndText, IUpdateable, IHasPage {

    private WifiPage _page;
    private string   connected_ssid = "";

    public WifiTray(Context ctx) {
        base(ctx, new HoverableIcon("wifi-unknown"), "WiFi");
        _page = new WifiPage();
        update();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()       { return _page; }
    public bool      is_icon_hovered(){ return icon.hovered; }

    // ── IUpdateable ───────────────────────────────────────────────────────

    public string get_status() { return connected_ssid; }

    public void update() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device",
                out out_str, null, null);
        } catch (SpawnError e) { return; }

        connected_ssid = "";
        foreach (var line in out_str.split("\n")) {
            var p = line.split(":");
            if (p.length >= 4 && p[1] == "wifi" && p[2] == "connected") {
                connected_ssid = p[3];
                break;
            }
        }

        icon.free();
        icon.load(connected_ssid != "" && connected_ssid != "--" ? "wifi" : "nowifi");
    }

    // ── Rendering ─────────────────────────────────────────────────────────

    public override void render(Context ctx) {
        if (!icon.hovered) {
            ctx.set_tex_color(connected_ssid != "" && connected_ssid != "--"
                ? DrawKit.Color(){r=0.25f, g=1.0f, b=0.45f, a=1f}
                : DrawKit.Color(){r=0.45f, g=0.45f, b=0.45f, a=1f});
        }
        icon.render(ctx);
        ctx.set_tex_color(DrawKit.Color(){r=1f, g=1f, b=1f, a=1f});
    }
}
