using Gtk;
using GLib;

// BatteryPage — full-panel battery information display.
//
// One custom widget; snapshot() draws the entire page directly so the
// visual matches the original DrawKit version pixel-for-pixel: dimmed
// title top-left, large color-coded percentage centered, status text
// below, custom progress bar (LumenProgressBar) with embedded label
// at the bottom, and a 2×2 stat grid for voltage / current / charge /
// est-time.
public class BatteryPage : Gtk.Widget {

    BatteryService service;
    PowerProfileService pps;
    LumenProgressBar progress;
    SegmentedControl profile_seg;

    // Layout constants — pixel-identical to the original.
    const int PAD       = 16;
    const int BAR_H     = 22;
    const int DY_TITLE  = PAD;
    const int DY_PCT    = DY_TITLE  + 26;
    const int DY_STATUS = DY_PCT    + 50;
    const int DY_BAR    = DY_STATUS + 24;
    const int DY_STAT1  = DY_BAR    + BAR_H + 14;
    const int DY_STAT2  = DY_STAT1  + 32;
    const int BASE_MIN_H = DY_STAT2 + 32;

    // Power-mode section, appended below the stat grid when a backend exists.
    const int DY_PROFILE_LABEL = BASE_MIN_H + 4;
    const int DY_PROFILE       = DY_PROFILE_LABEL + 20;
    const int PROFILE_MIN_H    = DY_PROFILE + SegmentedControl.CTRL_H + PAD;

    static Gdk.RGBA title_col      = Utils.rgba(0.62f, 0.64f, 0.72f, 1f);
    static Gdk.RGBA status_col     = Utils.rgba(0.60f, 0.62f, 0.70f, 1f);
    static Gdk.RGBA stat_label_col = Utils.rgba(0.42f, 0.44f, 0.52f, 1f);
    static Gdk.RGBA stat_value_col = Utils.rgba(0.84f, 0.86f, 0.92f, 1f);
    static Gdk.RGBA track_col      = Utils.rgba(0.10f, 0.11f, 0.16f, 1f);

    string pct_str    = "0%";
    string status_str = "—";
    string voltage_str = "";
    string current_str = "";
    string charge_str  = "";
    string time_str    = "";
    bool   has_time    = false;
    Gdk.RGBA pct_col   = Utils.rgba(1f, 1f, 1f, 1f);

    public BatteryPage (BatteryService service, PowerProfileService pps) {
        this.service = service;
        this.pps = pps;

        progress = new LumenProgressBar() {
            track_color = track_col,
        };
        progress.set_parent(this);

        profile_seg = new SegmentedControl();
        profile_seg.visible = pps.backend != PowerBackend.NONE;
        profile_seg.set_parent(this);
        profile_seg.segment_selected.connect((i) => {
            if (i >= 0 && i < pps.available.length) pps.select(pps.available[i]);
        });

        set_size_request(440, page_height());
        service.state_changed.connect(refresh);
        pps.state_changed.connect(refresh_profile);
        refresh();
        refresh_profile();
    }

    public override void dispose () {
        if (progress != null)    { progress.unparent();    progress = null; }
        if (profile_seg != null) { profile_seg.unparent(); profile_seg = null; }
        base.dispose();
    }

    int page_height () {
        return pps.backend != PowerBackend.NONE ? PROFILE_MIN_H : BASE_MIN_H;
    }

    public override void size_allocate (int width, int height, int baseline) {
        var transform = new Gsk.Transform().translate({ PAD, DY_BAR });
        progress.allocate(width - PAD * 2, BAR_H, baseline, transform);

        if (profile_seg.visible) {
            var pt = new Gsk.Transform().translate({ PAD, DY_PROFILE });
            profile_seg.allocate(width - PAD * 2, SegmentedControl.CTRL_H, baseline, pt);
        } else {
            profile_seg.allocate(0, 0, baseline, null);
        }
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size,
                                  out int min, out int nat,
                                  out int min_baseline, out int nat_baseline) {
        min_baseline = -1; nat_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            min = 440; nat = 440;
        } else {
            min = nat = page_height();
        }
    }

    string profile_label (PowerProfile p) {
        switch (p) {
            case PowerProfile.PERFORMANCE: return "Performance";
            case PowerProfile.BALANCED:    return "Balanced";
            case PowerProfile.POWER_SAVER: return "Power Saver";
            default:                       return "";
        }
    }

    void refresh_profile () {
        if (pps.backend == PowerBackend.NONE) return;

        string[] labels = {};
        int selected = -1;
        for (int i = 0; i < pps.available.length; i++) {
            labels += profile_label(pps.available[i]);
            if (pps.available[i] == pps.current) selected = i;
        }
        profile_seg.set_segments(labels);
        profile_seg.set_selected(selected);
    }

    void refresh () {
        var raw = service.raw_status;
        var pct = service.percent;

        if (raw == "charging")          status_str = "⚡ Charging";
        else if (raw == "discharging")  status_str = "Discharging";
        else if (raw.contains("full"))  status_str = "✓ Full";
        else                            status_str = raw.length > 0 ? raw : "Unknown";

        pct_str = "%d%%".printf(pct);
        pct_col = pct >= 60
            ? Utils.rgba(0.18f, 0.88f, 0.42f, 1f)
            : pct >= 25
                ? Utils.rgba(1.0f, 0.74f, 0.14f, 1f)
                : Utils.rgba(1.0f, 0.28f, 0.28f, 1f);

        progress.set_progress(pct);
        progress.fill_color = pct >= 60
            ? Utils.rgba(0.13f, 0.76f, 0.34f, 1f)
            : pct >= 25
                ? Utils.rgba(0.90f, 0.62f, 0.06f, 1f)
                : Utils.rgba(0.86f, 0.20f, 0.20f, 1f);

        voltage_str = "%.2f V".printf(service.voltage_v);
        current_str = "%.2f A".printf(service.current_a);
        charge_str  = "%d / %d mAh".printf(
            service.charge_now / 1000, service.charge_full / 1000);

        has_time = false;
        if (raw == "discharging" && service.current_a > 0.05f) {
            float hrs = (service.charge_now / 1000000f) / service.current_a;
            int h = (int) hrs;
            int m = (int)((hrs - h) * 60);
            time_str = h > 0 ? "%dh %dm left".printf(h, m) : "%dm left".printf(m);
            has_time = true;
        } else if (raw == "charging" && service.current_a > 0.05f) {
            float hrs = ((service.charge_full - service.charge_now) / 1000000f) / service.current_a;
            int h = (int) hrs;
            int m = (int)((hrs - h) * 60);
            time_str = h > 0 ? "%dh %dm to full".printf(h, m) : "%dm to full".printf(m);
            has_time = true;
        }

        queue_draw();
    }

    public override void snapshot (Gtk.Snapshot s) {
        int w = get_width();

        draw_text(s, "Battery", PAD, DY_TITLE, 16, title_col, false, Pango.Weight.NORMAL);
        draw_text(s, pct_str,   w / 2, DY_PCT, 40, pct_col,    true,  Pango.Weight.SEMIBOLD);
        draw_text(s, status_str, w / 2, DY_STATUS, 14, status_col, true, Pango.Weight.NORMAL);

        base.snapshot(s); // progress bar (LumenProgressBar)

        int col1 = PAD;
        int col2 = w / 2;
        draw_stat(s, col1, DY_STAT1, "Voltage", voltage_str);
        draw_stat(s, col2, DY_STAT1, "Current", current_str);
        draw_stat(s, col1, DY_STAT2, "Charge",  charge_str);
        if (has_time) draw_stat(s, col2, DY_STAT2, "Est. time", time_str);

        if (pps.backend != PowerBackend.NONE)
            draw_text(s, "Power Mode", PAD, DY_PROFILE_LABEL, 11,
                      stat_label_col, false, Pango.Weight.NORMAL);
    }

    void draw_stat (Gtk.Snapshot s, int x, int y, string label, string value) {
        draw_text(s, label, x, y,      11, stat_label_col, false, Pango.Weight.NORMAL);
        draw_text(s, value, x, y + 14, 14, stat_value_col, false, Pango.Weight.MEDIUM);
    }

    void draw_text (Gtk.Snapshot s, string text, int x, int y,
                    int size_pt, Gdk.RGBA color, bool center, Pango.Weight weight) {
        var layout = create_pango_layout(text);
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.AttrSize.new_absolute(size_pt * Pango.SCALE));
        attrs.insert(Pango.attr_weight_new(weight));
        layout.set_attributes(attrs);

        int tw, th;
        layout.get_pixel_size(out tw, out th);
        int px = center ? x - tw / 2 : x;
        int py = y;

        var pt = Graphene.Point();
        pt.init(px, py);
        s.save();
        s.translate(pt);
        s.append_layout(layout, color);
        s.restore();
    }
}
