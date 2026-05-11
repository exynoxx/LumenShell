using DrawKit;
using GLib;

/**
 * WifiTray — icon in the tray bar.
 *
 * Subscribes to WifiPage's shared WifiService; renders a tinted icon based
 * on the current connection state.
 */
public class WifiTray : IconAndText, IUpdateable, IHasPage {

    private WifiPage _page;

    public WifiTray() {
        base(new HoverableIcon("wifi-unknown"));
        _page = new WifiPage();
        _page.service.state_changed.connect(() => {
            update();
            redraw = true;
        });
        update();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()        { return _page; }
    public bool      is_icon_hovered() { return icon.hovered; }
    public void      set_page_active(bool active) { icon.selected = active; }

    // ── IUpdateable ───────────────────────────────────────────────────────

    public string get_status() { return _page.service.connected_ssid; }

    public void update() {
        icon.set_icon(_page.service.connected_ssid != "" ? "wifi" : "nowifi");
    }

    // ── Rendering ─────────────────────────────────────────────────────────

    public override void render(Context ctx) {
        if (!icon.hovered && !icon.selected) {
            DrawKit.Color tint = _page.service.connected_ssid != ""
                ? DrawKit.Color(){r=0.25f, g=1.0f,  b=0.45f, a=1f}
                : DrawKit.Color(){r=0.45f, g=0.45f, b=0.45f, a=1f};
            ctx.set_tex_color(tint);
        }
        icon.render(ctx);
        ctx.set_tex_color(DrawKit.Color(){r=1f, g=1f, b=1f, a=1f});
    }
}
