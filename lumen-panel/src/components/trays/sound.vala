using DrawKit;

public class SoundTray : GLib.Object, ITray, IHoverable, IHasPage {

    private HoverableIcon icon;
    private SoundPage _page;

    private int x     = 0;
    private int y     = 0;
    // Reserved at construction for the widest possible label so the tray
    // bar never shifts when the volume / mute label changes.
    private int width;

    private string label = "0%";
    private bool   muted = false;

    private Color label_col_normal = Color(){r=0.90f, g=0.92f, b=0.96f, a=1f};
    private Color label_col_muted  = Color(){r=0.92f, g=0.36f, b=0.36f, a=1f};

    public SoundTray(Context ctx) {
        icon  = new HoverableIcon("sound-max");
        _page = new SoundPage();

        // "100%" and "Muted" are the widest labels the tray will ever show.
        int max_label_w = int.max(ctx.width_of("100%",  13f),
                                  ctx.width_of("Muted", 13f));
        width = icon.get_width() + max_label_w;

        _page.state_changed.connect(() => {
            sync_from_page();
            redraw = true;
        });

        _page.refresh_state();
        sync_from_page();

        // Poll in the background so render() stays side-effect free.
        GLib.Timeout.add(1200, () => {
            _page.refresh_state();
            return Source.CONTINUE;
        });
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()        { return _page; }
    public bool      is_icon_hovered() { return icon.hovered; }
    public void      set_page_active(bool active) { icon.selected = active; }

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
        icon.render(ctx);

        int tx  = x + icon.get_width();
        int ty  = y + (Tray.TRAY_HEIGHT - 13) / 2;
        pdt(ctx, label, tx, ty, 13f, muted ? label_col_muted : label_col_normal);
    }

    private void sync_from_page() {
        muted = _page.is_muted();
        int pct = _page.get_volume_percent();
        label = "%d%%".printf(pct);
        icon.set_icon(muted ? "sound-mute" : "sound-max");
    }
}
