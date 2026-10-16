// The enclosing card clips the rounded corners, so the row paints a full-width
// selection fill.
public class WifiRow : Gtk.Widget, CcRow {

    public const int ROW_H = 44;
    const int PAD      = 16;
    const int NAME_X   = PAD + 26;   // text starts past the checkmark column
    const int ARC_W    = 24;
    const int LOCK_W   = 13;
    const int GAP      = 10;

    public string ssid       { get; private set; }
    public int    signal_pct { get; private set; }
    public bool   is_secured { get; private set; }

    public string key { get { return ssid; } }

    public signal void activated ();

    // Draw-affecting state: custom snapshot() means nothing repaints on its own.
    bool _is_connected = false;
    bool _selected = false;
    bool _show_separator = true;
    bool hovered = false;

    public bool is_connected {
        get { return _is_connected; }
        set { if (_is_connected == value) return; _is_connected = value; queue_draw (); }
    }

    public bool selected {
        get { return _selected; }
        set { if (_selected == value) return; _selected = value; queue_draw (); }
    }

    public bool show_separator {
        get { return _show_separator; }
        set { if (_show_separator == value) return; _show_separator = value; queue_draw (); }
    }

    static Gdk.RGBA lock_fg = Utils.rgba (0.921f, 0.921f, 0.960f, 0.45f);

    public WifiRow (WifiNet net, bool is_connected) {
        this.ssid = net.ssid;
        this.signal_pct = net.signal;
        this.is_secured = net.is_secured ();
        this._is_connected = is_connected;

        height_request = ROW_H;
        hexpand = true;

        var click = new Gtk.GestureClick () { button = Gdk.BUTTON_PRIMARY };
        click.released.connect (() => activated ());
        add_controller (click);

        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect (() => { hovered = true;  queue_draw (); });
        motion.leave.connect (() => { hovered = false; queue_draw (); });
        add_controller (motion);
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size,
                                  out int min, out int nat,
                                  out int min_baseline, out int nat_baseline) {
        min_baseline = -1; nat_baseline = -1;
        if (orientation == Gtk.Orientation.HORIZONTAL) { min = 220; nat = 480; }
        else                                           { min = nat = ROW_H; }
    }

    public override void snapshot (Gtk.Snapshot s) {
        int w = get_width ();
        int h = get_height ();

        if (_selected || hovered)
            Utils.fill_rounded (s, 0, 0, w, h, 0,
                                _selected ? CcStyle.row_selected : CcStyle.row_hover);

        if (_is_connected) {
            var check = Utils.text_layout (this, "✓", 15, Pango.Weight.BOLD);
            int cw, ch;
            check.get_pixel_size (out cw, out ch);
            Utils.draw_layout (s, check, PAD - 2, (h - ch) / 2, CcStyle.green);
        }

        var layout = Utils.text_layout (this, ssid, 15, Pango.Weight.MEDIUM);
        int right_reserve = PAD + ARC_W + GAP + (is_secured ? LOCK_W + GAP : 0);
        layout.set_width ((w - NAME_X - right_reserve) * Pango.SCALE);
        layout.set_ellipsize (Pango.EllipsizeMode.END);
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        Utils.draw_layout (s, layout, NAME_X, (h - th) / 2,
                           _is_connected ? CcStyle.green : CcStyle.label);

        float arc_cx = w - PAD - ARC_W / 2.0f;
        WifiArc.draw (s, arc_cx, h / 2.0f + 6, signal_pct, CcStyle.label);

        if (is_secured) {
            float lock_x = w - PAD - ARC_W - GAP - LOCK_W;
            draw_lock (s, lock_x, h / 2.0f - LOCK_W / 2.0f, LOCK_W, lock_fg);
        }

        if (_show_separator)
            Utils.fill_rounded (s, NAME_X, h - 1, w - PAD - NAME_X, 1, 0, CcStyle.separator);
    }

    static void draw_lock (Gtk.Snapshot s, float x, float y, float sz, Gdk.RGBA c) {
        float bh = sz * 0.60f;
        float by = y + sz - bh;

        Utils.fill_rounded (s, x, by, sz, bh, sz * 0.18f, c);

        float sr = sz * 0.30f;
        float scx = x + sz / 2.0f;
        float top = by - sr * 0.55f;
        var b = new Gsk.PathBuilder ();
        b.move_to (scx - sr, by);
        b.line_to (scx - sr, top);
        b.svg_arc_to (sr, sr, 0f, false, true, scx + sr, top);
        b.line_to (scx + sr, by);
        var stroke = new Gsk.Stroke (1.3f);
        stroke.set_line_cap (Gsk.LineCap.ROUND);
        s.append_stroke (b.to_path (), stroke, c);
    }
}
