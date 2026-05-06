using DrawKit;

public class SoundTray : GLib.Object, ITray, IHoverable, IHasPage {

    private unowned Context ctx;
    private HoverableIcon icon;
    private SoundPage _page;

    private int x = 0;
    private int y = 0;
    private int width = 62;

    private string label = "0%";
    private bool muted = false;
    private int last_poll_us = 0;

    public SoundTray(Context ctx) {
        this.ctx = ctx;
        icon = new HoverableIcon("sound-max");
        _page = new SoundPage();
        _page.state_changed.connect(() => {
            sync_from_page();
            redraw = true;
        });

        _page.refresh_state(false);
        sync_from_page();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page() { return _page; }
    public bool is_icon_hovered() { return icon.hovered; }
    public void set_page_active(bool active) { icon.selected = active; }

    // ── ITray / IHoverable ────────────────────────────────────────────────

    public int get_width() { return width; }

    public void set_position(int x, int y) {
        this.x = x;
        this.y = y;
        icon.set_position(x, y);
    }

    public void mouse_motion(int mx, int my) {
        icon.mouse_motion(mx, my);
    }

    public void render(Context ctx) {
        int now_us = (int) GLib.get_monotonic_time();
        if (now_us - last_poll_us > 1200000) {
            _page.refresh_state(false);
            sync_from_page();
            last_poll_us = now_us;
        }

        icon.render(ctx);

        int tx = x + icon.get_width() + 2;
        int ty = y + (Tray.TRAY_HEIGHT - 13) / 2;
        Color col = muted
            ? Color(){r=0.92f, g=0.36f, b=0.36f, a=1f}
            : Color(){r=0.90f, g=0.92f, b=0.96f, a=1f};
        pdt(ctx, label, tx, ty, 13f, col);
    }

    private void sync_from_page() {
        muted = _page.is_muted();
        int pct = _page.get_volume_percent();
        label = "%d%%".printf(pct);
        icon.set_icon(muted ? "sound-mute" : "sound-max");
        width = icon.get_width() + 2 + ctx.width_of(label, 13f);
    }
}
