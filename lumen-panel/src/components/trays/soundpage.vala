using DrawKit;
using GLib;

public class SoundPage : GLib.Object, ITrayPage {

    public signal void state_changed();

    private const int PAD      = 14;
    private const int HEADER_H = 44;
    private const int SLIDER_H = 42;
    private const int ROW_H    = 34;

    private const int TITLE_TOP_OFFSET = (HEADER_H - 20) / 2;  // 12
    private const int CTRL_Y_OFFSET    = (HEADER_H - 24) / 2;  // 10

    private class SinkRow : GLib.Object {
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

    private PactlClient pactl = new PactlClient();

    private SinkRow[] sink_rows    = {};
    private string    default_sink = "";
    private int       volume_percent = 0;
    private bool      muted          = false;

    private UiHorizontalSlider slider      = new UiHorizontalSlider();
    private UiButton           mute_button = new UiButton();

    private int px = 0;
    private int py = 0;
    private int pw = 0;
    private int ph = 0;

    private uint refresh_timer_id = 0;

    // Cached display values — updated in apply_mute_visuals()
    private string cached_pct_txt = "";
    private Color  cached_pct_col;
    private int    cached_pct_w   = -1;  // text-width cache, -1 = dirty

    // Cached separator color
    private Color sep_color = Color(){r=0.22f, g=0.24f, b=0.35f, a=0.7f};

    public SoundPage() {
        slider.value_changed.connect((v) => set_volume_percent(v));
        slider.track_color = Color(){r=0.14f, g=0.15f, b=0.22f, a=1f};

        mute_button.label         = "Mute";
        mute_button.text_size     = 11f;
        mute_button.radius        = 8f;
        mute_button.normal_color  = Color(){r=0.16f, g=0.18f, b=0.24f, a=1f};
        mute_button.hover_color   = Color(){r=0.25f, g=0.27f, b=0.35f, a=1f};
        mute_button.pressed_color = Color(){r=0.13f, g=0.15f, b=0.21f, a=1f};
        mute_button.clicked.connect(() => toggle_mute());
    }

    public string get_title()        { return "Sound"; }
    public int    get_volume_percent() { return volume_percent; }
    public bool   is_muted()           { return muted; }

    public void on_activate() {
        refresh_state();
        if (refresh_timer_id == 0)
            refresh_timer_id = GLib.Timeout.add(1500, () => {
                refresh_state();
                return Source.CONTINUE;
            });
    }

    public void on_deactivate() {
        if (refresh_timer_id != 0) {
            GLib.Source.remove(refresh_timer_id);
            refresh_timer_id = 0;
        }
        slider.mouse_up(-1, -1);
        mute_button.cancel_press();
        foreach (var row in sink_rows)
            row.cancel_press();
    }

    public void refresh_state() {
        default_sink   = pactl.query_default_sink();
        var raw_sinks  = pactl.query_sinks();
        volume_percent = pactl.query_volume_percent();
        muted          = pactl.query_muted();
        slider.set_value(volume_percent);

        // Rebuild pool only when the set of sinks actually changes
        bool same = sink_rows.length == raw_sinks.length;
        if (same) {
            for (int i = 0; i < sink_rows.length; i++) {
                if (sink_rows[i].id != raw_sinks[i].id) { same = false; break; }
            }
        }
        if (!same) {
            sink_rows = {};
            for (int i = 0; i < raw_sinks.length; i++) {
                int idx = i;  // capture i for closure
                var row = new SinkRow();
                row.update(raw_sinks[i].id, raw_sinks[i].name);
                row.selected.connect(() => {
                    set_default_sink(sink_rows[idx].id);
                });
                sink_rows += row;
            }
        } else {
            for (int i = 0; i < sink_rows.length; i++)
                sink_rows[i].update(raw_sinks[i].id, raw_sinks[i].name);
        }

        apply_mute_visuals();
        state_changed();
        redraw = true;
    }

    public void render(Context ctx, int x, int y, int w, int h) {
        px = x;  py = y;  pw = w;  ph = h;

        // ── Header ───────────────────────────────────────────────────────
        pdt(ctx, "Sound", x + PAD, y + TITLE_TOP_OFFSET, 20f, Color(){r=1f, g=1f, b=1f, a=1f});

        if (cached_pct_w < 0) cached_pct_w = ctx.width_of(cached_pct_txt, 12.5f);
        int chip_w = cached_pct_w + 18;
        int mute_x = x + w - PAD - 48;
        int chip_x = mute_x - 8 - chip_w;
        int chip_y = y + CTRL_Y_OFFSET;

        ctx.draw_rect_rounded(chip_x, chip_y, chip_w, 24, 12f, Color(){r=0.11f, g=0.13f, b=0.19f, a=1f});
        pdt(ctx, cached_pct_txt, chip_x + 9, chip_y + 4, 12.5f, cached_pct_col);

        mute_button.set_bounds(mute_x, chip_y, 48, 24);
        mute_button.render(ctx);

        // ── Separator ────────────────────────────────────────────────────
        int sep_y = y + HEADER_H;
        ctx.draw_rect(x + PAD, sep_y, w - PAD * 2, 1, sep_color);

        // ── Volume slider ────────────────────────────────────────────────
        int slider_y = sep_y + 14;
        slider.set_bounds(x + PAD, slider_y, w - PAD * 2, SLIDER_H);
        slider.render(ctx);
        pdt(ctx, cached_pct_txt, x + PAD, slider_y + SLIDER_H - 14, 12f, Color(){r=0.72f, g=0.75f, b=0.84f, a=1f});

        // ── Device list ──────────────────────────────────────────────────
        int list_top = slider_y + SLIDER_H + 8;
        pdt(ctx, "Output device", x + PAD, list_top, 12f, Color(){r=0.55f, g=0.57f, b=0.66f, a=1f});

        int rows_top = list_top + 16;
        int max_rows = (h - (rows_top - y) - 8) / ROW_H;
        if (max_rows <= 0) return;

        if (sink_rows.length == 0) {
            pdt_center(ctx, "No output devices", x + w / 2, rows_top + 8, 13f, Color(){r=0.48f, g=0.50f, b=0.58f, a=1f});
            return;
        }

        int rows = int.min(max_rows, sink_rows.length);
        for (int i = 0; i < rows; i++) {
            sink_rows[i].set_bounds(x + 6, rows_top + i * ROW_H, w - 12, ROW_H);
            sink_rows[i].render(ctx, sink_rows[i].id == default_sink);
        }
    }

    public void mouse_down(int mx, int my) {
        mute_button.mouse_down(mx, my);
        slider.mouse_down(mx, my);
        foreach (var row in sink_rows)
            row.mouse_down(mx, my);
    }

    public void mouse_up(int mx, int my) {
        mute_button.mouse_up(mx, my);
        slider.mouse_up(mx, my);
        foreach (var row in sink_rows)
            row.mouse_up(mx, my);
    }

    public void mouse_motion(int mx, int my) {
        slider.mouse_motion(mx, my);
        mute_button.mouse_motion(mx, my);
        foreach (var row in sink_rows)
            row.mouse_motion(mx, my);
    }

    public void mouse_scroll(int mx, int my, int amount) {
        if (amount == 0) return;
        set_volume_percent(volume_percent + (amount > 0 ? -3 : 3));
    }

    // Synchronises all mute-dependent display state.
    // Must be called whenever muted or volume_percent changes.
    private void apply_mute_visuals() {
        cached_pct_txt = muted ? "Muted" : "%d%%".printf(volume_percent);
        cached_pct_w   = -1;  // invalidate text-width cache
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

    private void set_volume_percent(int pct) {
        pct = int.max(0, int.min(100, pct));
        if (pct == volume_percent && !muted) return;

        pactl.run_cmd_async("pactl set-sink-volume @DEFAULT_SINK@ %d%%".printf(pct));

        volume_percent = pct;
        slider.set_value(volume_percent);
        if (muted) {
            muted = false;
            pactl.run_cmd_async("pactl set-sink-mute @DEFAULT_SINK@ 0");
        }
        apply_mute_visuals();
        state_changed();
        redraw = true;
    }

    private void toggle_mute() {
        pactl.run_cmd_async("pactl set-sink-mute @DEFAULT_SINK@ toggle");
        muted = !muted;
        apply_mute_visuals();
        state_changed();
        redraw = true;
    }

    private void set_default_sink(string sink_id) {
        if (sink_id == "") return;
        pactl.run_cmd_async("pactl set-default-sink " + pactl.shell_quote(sink_id));
        default_sink = sink_id;
        state_changed();
        redraw = true;
    }
}
