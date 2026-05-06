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

    private enum LinkState {
        UNKNOWN,
        OFFLINE,
        ONLINE
    }

    private LinkState link_state = LinkState.UNKNOWN;

    public WifiTray(Context ctx) {
        base(ctx, new HoverableIcon("wifi-unknown"), "WiFi");
        _page = new WifiPage();
        _page.state_changed.connect(() => {
            update();
            redraw = true;
        });
        update();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()       { return _page; }
    public bool      is_icon_hovered(){ return icon.hovered; }
    public void      set_page_active(bool active) { icon.selected = active; }

    // ── IUpdateable ───────────────────────────────────────────────────────

    public string get_status() { return connected_ssid; }

    public void update() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device",
                out out_str, null, null);
        } catch (SpawnError e) {
            link_state = LinkState.UNKNOWN;
            connected_ssid = "";
            apply_icon();
            return;
        }

        connected_ssid = "";
        bool has_wifi_device = false;

        foreach (var line in out_str.split("\n")) {
            var p = split_nmcli_terse(line, 4);
            if (p.length < 4 || p[1] != "wifi")
                continue;

            has_wifi_device = true;
            if (p[2] == "connected" && p[3] != "" && p[3] != "--") {
                connected_ssid = p[3];
                break;
            }
        }

        if (!has_wifi_device) {
            link_state = LinkState.UNKNOWN;
        } else if (connected_ssid != "") {
            link_state = LinkState.ONLINE;
        } else {
            link_state = LinkState.OFFLINE;
        }

        apply_icon();
    }

    private void apply_icon() {
        switch (link_state) {
        case LinkState.ONLINE:
            icon.set_icon("wifi");
            break;
        case LinkState.OFFLINE:
            icon.set_icon("nowifi");
            break;
        default:
            icon.set_icon("wifi-unknown");
            break;
        }
    }

    // ── Rendering ─────────────────────────────────────────────────────────

    public override void render(Context ctx) {
        if (!icon.hovered && !icon.selected) {
            DrawKit.Color tint;
            switch (link_state) {
            case LinkState.ONLINE:
                tint = DrawKit.Color(){r=0.25f, g=1.0f, b=0.45f, a=1f};
                break;
            case LinkState.OFFLINE:
                tint = DrawKit.Color(){r=0.45f, g=0.45f, b=0.45f, a=1f};
                break;
            default:
                tint = DrawKit.Color(){r=1.0f, g=0.78f, b=0.26f, a=1f};
                break;
            }
            ctx.set_tex_color(tint);
        }
        icon.render(ctx);
        ctx.set_tex_color(DrawKit.Color(){r=1f, g=1f, b=1f, a=1f});
    }

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
