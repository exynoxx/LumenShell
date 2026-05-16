using DrawKit;
using GLib;

/**
 * WifiTray — icon in the tray bar.
 *
 * Owns the shared WifiService and hands it to WifiPage. Renders a tinted
 * icon based on the current connection state.
 */
public class WifiTray : IconAndText, IUpdateable, IHasPage {

    private WifiService _service;
    private WifiPage    _page;

    private DrawKit.Color tint_color;
    private DrawKit.Color tint_connected    = DrawKit.Color(){r=0.25f, g=1.0f,  b=0.45f, a=1f};
    private DrawKit.Color tint_disconnected = DrawKit.Color(){r=0.45f, g=0.45f, b=0.45f, a=1f};
    private DrawKit.Color tint_neutral      = DrawKit.Color(){r=1f,    g=1f,    b=1f,    a=1f};

    public WifiTray() {
        base(new HoverableIcon("wifi-unknown"));
        _service = new WifiService();
        _page    = new WifiPage(_service);
        _service.state_changed.connect(() => {
            update();
            redraw = true;
        });
        update();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()                    { return _page; }
    public bool      is_icon_hovered()             { return icon.hovered; }
    public void      set_page_active(bool active)  { icon.selected = active; }

    // ── IUpdateable ───────────────────────────────────────────────────────

    public string get_status() { return _service.connected_ssid; }

    public void update() {
        icon.set_icon(_service.connected ? "wifi" : "nowifi");
        tint_color = _service.connected ? tint_connected : tint_disconnected;
    }

    // ── Rendering ─────────────────────────────────────────────────────────

    public override void render(Context ctx) {
        if (!icon.hovered && !icon.selected)
            ctx.set_tex_color(tint_color);
        icon.render(ctx);
        ctx.set_tex_color(tint_neutral);
    }
}
