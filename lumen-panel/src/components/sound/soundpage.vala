using DrawKit;
using GLib;

/**
 * SoundPage — volume slider, mute toggle, output device picker.
 *
 * The SoundService is injected so the same instance is shared with SoundTray.
 */
public class SoundPage : BaseTrayPage {

    // ── Layout constants ──────────────────────────────────────────────────
    private const int PAD       = 14;
    private const int HEADER_H  = 44;
    private const int SLIDER_H  = 42;
    private const int ROW_H     = 34;

    private const int DY_TITLE  = (HEADER_H - 20) / 2;     // 12
    private const int DY_CTRL   = (HEADER_H - 24) / 2;     // 10
    private const int DY_SEP    = HEADER_H;                // 44
    private const int DY_SLIDER = DY_SEP + 14;             // 58
    private const int DY_LIST   = DY_SLIDER + SLIDER_H + 8; // 108
    private const int DY_ROWS   = DY_LIST + 16;             // 124

    private const int MUTE_BTN_W = 48;
    private const int CHIP_PAD   = 18;

    // ── Cached colours ────────────────────────────────────────────────────
    private Color title_col      = Color(){r=1f,    g=1f,    b=1f,    a=1f};
    private Color chip_bg_col    = Color(){r=0.11f, g=0.13f, b=0.19f, a=1f};
    private Color slider_lbl_col = Color(){r=0.72f, g=0.75f, b=0.84f, a=1f};
    private Color list_label_col = Color(){r=0.55f, g=0.57f, b=0.66f, a=1f};
    private Color empty_text_col = Color(){r=0.48f, g=0.50f, b=0.58f, a=1f};
    private Color slider_track   = Color(){r=0.14f, g=0.15f, b=0.22f, a=1f};

    // ── Service (injected) ────────────────────────────────────────────────
    private SoundService service;

    // ── Children ──────────────────────────────────────────────────────────
    private SinkRowList         sink_rows   = new SinkRowList();
    private UiHorizontalSlider  slider      = new UiHorizontalSlider();
    private UiButton            mute_button = new UiButton();

    // ── Layout — derived from bounds, locked once ─────────────────────────
    private int slider_w  = 0;
    private int row_w     = 0;
    private int row_dx    = 0;
    private int max_rows  = 0;

    // ── Cached display values ─────────────────────────────────────────────
    private string cached_pct_txt = "";
    private Color  cached_pct_col;
    private int    cached_pct_w   = -1;  // text-width cache, -1 = dirty

    // Reserved chip text width: max of "100%" / "Muted". Computed once on
    // the first render() so the chip never resizes as the label changes.
    private int  chip_reserved_text_w = 0;
    private bool chip_metrics_ready   = false;

    public SoundPage(SoundService service) {
        this.service = service;

        slider.value_changed.connect((v) => service.change_volume(v));
        slider.track_color = slider_track;

        mute_button.label         = "Mute";
        mute_button.text_size     = 11f;
        mute_button.radius        = 8f;
        mute_button.normal_color  = Color(){r=0.16f, g=0.18f, b=0.24f, a=1f};
        mute_button.hover_color   = Color(){r=0.25f, g=0.27f, b=0.35f, a=1f};
        mute_button.pressed_color = Color(){r=0.13f, g=0.15f, b=0.21f, a=1f};
        mute_button.clicked.connect(() => service.toggle_mute());

        service.state_changed.connect(on_service_changed);
        sink_rows.sink_selected.connect((id) => service.change_default_sink(id));

        sync_from_service();
    }

    protected override void on_bounds_set() {
        slider_w  = bounds_w - PAD * 2;
        row_w     = bounds_w - 12;
        row_dx    = 6;
        recompute_max_rows();
    }

    public override string get_title() { return "Sound"; }

    public override void on_activate() {
        service.refresh();
    }

    public override void on_deactivate() {
        slider.mouse_up(-1, -1);
        mute_button.cancel_press();
        sink_rows.cancel_all_press();
    }

    // ─────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────

    protected override void render_content(Context ctx, int x, int y) {
        // First-render: reserve the chip's max text width once.
        if (!chip_metrics_ready) {
            chip_reserved_text_w = int.max(ctx.width_of("100%",  12.5f),
                                           ctx.width_of("Muted", 12.5f));
            chip_metrics_ready = true;
        }
        if (cached_pct_w < 0) cached_pct_w = ctx.width_of(cached_pct_txt, 12.5f);

        // Header
        pdt(ctx, "Sound", x + PAD, y + DY_TITLE, 20f, title_col);

        int chip_w = chip_reserved_text_w + CHIP_PAD;
        int mute_x = x + bounds_w - PAD - MUTE_BTN_W;
        int chip_x = mute_x - 8 - chip_w;
        int chip_y = y + DY_CTRL;

        ctx.draw_rect_rounded(chip_x, chip_y, chip_w, 24, 12f, chip_bg_col);
        int chip_text_left = chip_x + chip_w - 9 - cached_pct_w;
        pdt(ctx, cached_pct_txt, chip_text_left, chip_y + 4, 12.5f, cached_pct_col);

        mute_button.set_bounds(mute_x, chip_y, MUTE_BTN_W, 24);
        mute_button.render(ctx);

        // Separator
        ctx.draw_rect(x + PAD, y + DY_SEP, bounds_w - PAD * 2, 1, sep_color);

        // Slider
        int slider_y = y + DY_SLIDER;
        slider.set_bounds(x + PAD, slider_y, slider_w, SLIDER_H);
        slider.render(ctx);
        pdt(ctx, cached_pct_txt, x + PAD, slider_y + SLIDER_H - 14, 12f, slider_lbl_col);

        // Device list
        pdt(ctx, "Output device", x + PAD, y + DY_LIST, 12f, list_label_col);

        if (max_rows <= 0) return;
        if (sink_rows.length == 0) {
            pdt_center(ctx, "No output devices",
                x + bounds_w / 2, y + DY_ROWS + 8, 13f, empty_text_col);
            return;
        }

        int rows_y      = y + DY_ROWS;
        string selected = service.default_sink;
        int n           = int.min(max_rows, sink_rows.length);
        for (int i = 0; i < n; i++) {
            var row = sink_rows.at(i);
            row.set_bounds(x + row_dx, rows_y + i * ROW_H, row_w, ROW_H);
            row.render(ctx, row.id == selected);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Input
    // ─────────────────────────────────────────────────────────────────────

    public override void mouse_down(int mx, int my) {
        mute_button.mouse_down(mx, my);
        slider.mouse_down(mx, my);
        sink_rows.mouse_down(mx, my);
    }

    public override void mouse_up(int mx, int my) {
        mute_button.mouse_up(mx, my);
        slider.mouse_up(mx, my);
        sink_rows.mouse_up(mx, my);
    }

    public override void mouse_motion(int mx, int my) {
        slider.mouse_motion(mx, my);
        mute_button.mouse_motion(mx, my);
        sink_rows.mouse_motion(mx, my);
    }

    public override void mouse_scroll(int mx, int my, int amount) {
        if (amount == 0) return;
        service.change_volume(service.volume_percent + (amount > 0 ? -3 : 3));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Service callback / display sync
    // ─────────────────────────────────────────────────────────────────────

    private void on_service_changed() {
        sync_from_service();
        redraw = true;
    }

    private void sync_from_service() {
        slider.set_value(service.volume_percent);
        sink_rows.sync(service.sinks);
        apply_mute_visuals();
    }

    // Synchronises all mute-dependent display state. Called whenever
    // service state (muted or volume) changes.
    private void apply_mute_visuals() {
        bool muted = service.muted;
        cached_pct_txt = muted ? "Muted" : "%d%%".printf(service.volume_percent);
        cached_pct_w   = -1;
        cached_pct_col = muted
            ? Color(){r=0.90f, g=0.34f, b=0.34f, a=1f}
            : Color(){r=0.18f, g=0.88f, b=0.42f, a=1f};
        mute_button.label = muted ? "Unmute" : "Mute";
        mute_button.normal_color  = muted ? Color(){r=0.78f, g=0.20f, b=0.20f, a=1f} : Color(){r=0.16f, g=0.18f, b=0.24f, a=1f};
        mute_button.hover_color   = muted ? Color(){r=0.88f, g=0.28f, b=0.28f, a=1f} : Color(){r=0.25f, g=0.27f, b=0.35f, a=1f};
        mute_button.pressed_color = muted ? Color(){r=0.68f, g=0.16f, b=0.16f, a=1f} : Color(){r=0.13f, g=0.15f, b=0.21f, a=1f};
        slider.fill_color = muted
            ? Color(){r=0.72f, g=0.24f, b=0.24f, a=1f}
            : Color(){r=0.18f, g=0.62f, b=1.0f,  a=1f};
    }

    private void recompute_max_rows() {
        max_rows = (bounds_h - DY_ROWS - 8) / ROW_H;
        if (max_rows < 0) max_rows = 0;
    }
}

// ─────────────────────────────────────────────────────────────────────────
// SinkRow — one row in the device picker. Knows its own hit-rect and emits
// `selected` when clicked. Stored in a tiny collection (SinkRowList) so the
// page can talk to the whole list with one verb.
// ─────────────────────────────────────────────────────────────────────────
internal class SinkRow : GLib.Object {
    public signal void selected();

    private string _id   = "";
    private string _name = "";
    private int rx = 0;
    private int ry = 0;
    private int rw = 0;
    private int rh = 0;
    private bool hovered = false;
    private bool pressed = false;

    public string id   { get { return _id;   } }
    public string name { get { return _name; } }

    public void update(string id, string name) {
        _id   = id;
        _name = name;
    }

    public void set_bounds(int x, int y, int w, int h) {
        rx = x;  ry = y;  rw = w;  rh = h;
    }

    public bool contains(int mx, int my) {
        return mx >= rx && mx <= rx + rw
            && my >= ry + 3 && my <= ry + rh - 3;
    }

    public void mouse_motion(int mx, int my) {
        bool old = hovered;
        hovered = contains(mx, my);
        if (old != hovered) redraw = true;
    }

    public void mouse_down(int mx, int my) {
        if (contains(mx, my)) pressed = true;
    }

    public void mouse_up(int mx, int my) {
        if (pressed && contains(mx, my)) selected();
        pressed = false;
    }

    public void cancel_press() { pressed = false; }

    public void render(Context ctx, bool is_sel) {
        if (is_sel) {
            ctx.draw_rect_rounded(rx, ry + 3, rw, rh - 6, 8f, Color(){r=0.11f, g=0.27f, b=0.66f, a=0.90f});
        } else if (hovered) {
            ctx.draw_rect_rounded(rx, ry + 3, rw, rh - 6, 8f, Color(){r=0.17f, g=0.18f, b=0.24f, a=0.85f});
        }

        pdt(ctx, _name, rx + 10, ry + (rh - 13) / 2, 13f,
            is_sel ? Color(){r=1f, g=1f, b=1f, a=1f}
                   : Color(){r=0.86f, g=0.88f, b=0.93f, a=1f});

        if (is_sel)
            pdt(ctx, "✓", rx + rw - 18, ry + (rh - 13) / 2, 13f, Color(){r=0.22f, g=0.95f, b=0.48f, a=1f});
    }
}

/**
 * SinkRowList — owns the row pool and emits a callback when the user
 * picks one. The SoundPage interacts with the list as a whole rather
 * than reaching into the individual SinkRow instances.
 */
internal class SinkRowList : GLib.Object {

    public signal void sink_selected(string sink_id);

    private SinkRow[] rows = {};

    public int length { get { return rows.length; } }

    public SinkRow at(int i) { return rows[i]; }

    public void sync(SinkInfo[] infos) {
        bool same = rows.length == infos.length;
        if (same) {
            for (int i = 0; i < rows.length; i++) {
                if (rows[i].id != infos[i].id) { same = false; break; }
            }
        }

        if (!same) {
            rows = {};
            for (int i = 0; i < infos.length; i++) {
                int idx = i;
                var row = new SinkRow();
                row.update(infos[i].id, infos[i].name);
                row.selected.connect(() => sink_selected(rows[idx].id));
                rows += row;
            }
        } else {
            for (int i = 0; i < rows.length; i++)
                rows[i].update(infos[i].id, infos[i].name);
        }
    }

    public void mouse_motion(int mx, int my) {
        foreach (var r in rows) r.mouse_motion(mx, my);
    }

    public void mouse_down(int mx, int my) {
        foreach (var r in rows) r.mouse_down(mx, my);
    }

    public void mouse_up(int mx, int my) {
        foreach (var r in rows) r.mouse_up(mx, my);
    }

    public void cancel_all_press() {
        foreach (var r in rows) r.cancel_press();
    }
}
