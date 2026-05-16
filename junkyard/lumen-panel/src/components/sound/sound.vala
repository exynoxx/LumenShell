using DrawKit;

public class SoundTray : GLib.Object, ITray, IHoverable, IHasPage {

    private HoverableIcon icon;
    private SoundService  _service;
    private SoundPage     _page;

    private int x = 0;
    private int y = 0;
    // Reserved at construction for the widest possible label so the tray
    // bar never shifts when the volume / mute label changes.
    private int width;

    // Label position — precomputed in set_position so render() only draws.
    private int label_x = 0;
    private int label_y = 0;

    private string label = "0%";
    private bool   muted = false;

    private Color label_col_normal = Color(){r=0.90f, g=0.92f, b=0.96f, a=1f};
    private Color label_col_muted  = Color(){r=0.92f, g=0.36f, b=0.36f, a=1f};

    public SoundTray(Context ctx) {
        icon     = new HoverableIcon("sound-max");
        _service = new SoundService();
        _page    = new SoundPage(_service);

        // "100%" and "Muted" are the widest labels the tray will ever show.
        int max_label_w = int.max(ctx.width_of("100%",  13f),
                                  ctx.width_of("Muted", 13f));
        width = icon.get_width() + max_label_w;

        _service.state_changed.connect(() => {
            sync_from_service();
            redraw = true;
        });

        sync_from_service();
    }

    // ── IHasPage ──────────────────────────────────────────────────────────

    public ITrayPage get_page()                   { return _page; }
    public bool      is_icon_hovered()            { return icon.hovered; }
    public void      set_page_active(bool active) { icon.selected = active; }

    // ── ITray / IHoverable ────────────────────────────────────────────────

    public int get_width() { return width; }

    public void set_position(int x, int y) {
        this.x = x;
        this.y = y;
        icon.set_position(x, y);
        label_x = x + icon.get_width();
        label_y = y + (Tray.TRAY_HEIGHT - 13) / 2;
    }

    public void mouse_motion(int mx, int my) {
        icon.mouse_motion(mx, my);
    }

    public void render(Context ctx) {
        icon.render(ctx);
        pdt(ctx, label, label_x, label_y, 13f, muted ? label_col_muted : label_col_normal);
    }

    private void sync_from_service() {
        muted = _service.muted;
        label = "%d%%".printf(_service.volume_percent);
        icon.set_icon(muted ? "sound-mute" : "sound-max");
    }
}
