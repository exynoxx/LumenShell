using Gtk;

// One network cell inside a grouped .cc-card. macOS layout: a leading blue
// checkmark when connected, the SSID, then a trailing lock (secured) and the
// 3-arc Wi-Fi glyph. The card clips the rounded corners, so the row just paints
// a full-width selection fill and a hairline separator inset to the text.
// Everything is GSK (rounded clips, path stroke/fill) — GPU-rasterized.
public class WifiRow : Gtk.Widget {

    public const int ROW_H = 44;
    const int PAD      = 16;
    const int NAME_X   = PAD + 26;   // text starts past the checkmark column
    const int ARC_W    = 24;
    const int LOCK_W   = 13;
    const int GAP      = 10;

    public string ssid         { get; private set; }
    public int    signal_pct   { get; private set; }
    public bool   is_secured   { get; private set; }
    public bool   is_connected { get; set; }
    public bool   selected     { get; set; }
    public bool   show_separator { get; set; default = true; }

    public signal void activated ();

    bool hovered = false;

    static Gdk.RGBA sel_fill = Utils.rgba (0.039f, 0.518f, 1.0f, 0.18f);
    static Gdk.RGBA hov_fill = Utils.rgba (1f, 1f, 1f, 0.06f);
    static Gdk.RGBA name_fg  = Utils.rgba (1f, 1f, 1f, 1f);
    static Gdk.RGBA lock_fg  = Utils.rgba (0.921f, 0.921f, 0.960f, 0.45f);
    static Gdk.RGBA sep_fg   = Utils.rgba (1f, 1f, 1f, 0.10f);

    public WifiRow (WifiNet net, bool is_connected) {
        this.ssid = net.ssid;
        this.signal_pct = net.signal;
        this.is_secured = net.is_secured ();
        this.is_connected = is_connected;

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

        if (selected || hovered) {
            var rect = Graphene.Rect ();
            rect.init (0, 0, w, h);
            s.append_color (selected ? sel_fill : hov_fill, rect);
        }

        // Leading checkmark for the connected network.
        if (is_connected) {
            var check = create_pango_layout ("✓");
            var ca = new Pango.AttrList ();
            ca.insert (Pango.AttrSize.new_absolute (15 * Pango.SCALE));
            ca.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
            check.set_attributes (ca);
            int cw, ch;
            check.get_pixel_size (out cw, out ch);
            var cp = Graphene.Point ();
            cp.init (PAD - 2, (h - ch) / 2);
            s.save (); s.translate (cp);
            s.append_layout (check, CcStyle.accent);
            s.restore ();
        }

        // SSID.
        var layout = create_pango_layout (ssid);
        var attrs = new Pango.AttrList ();
        attrs.insert (Pango.AttrSize.new_absolute (15 * Pango.SCALE));
        attrs.insert (Pango.attr_weight_new (Pango.Weight.MEDIUM));
        layout.set_attributes (attrs);

        int right_reserve = PAD + ARC_W + GAP + (is_secured ? LOCK_W + GAP : 0);
        layout.set_width ((w - NAME_X - right_reserve) * Pango.SCALE);
        layout.set_ellipsize (Pango.EllipsizeMode.END);
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        var pt = Graphene.Point ();
        pt.init (NAME_X, (h - th) / 2);
        s.save (); s.translate (pt);
        s.append_layout (layout, name_fg);
        s.restore ();

        // Trailing glyphs.
        float arc_cx = w - PAD - ARC_W / 2.0f;
        WifiArc.draw (s, arc_cx, h / 2.0f + 6, signal_pct, name_fg);

        if (is_secured) {
            float lock_x = w - PAD - ARC_W - GAP - LOCK_W;
            draw_lock (s, lock_x, h / 2.0f - LOCK_W / 2.0f, LOCK_W, lock_fg);
        }

        // Hairline separator inset to the text column.
        if (show_separator) {
            var sep = Graphene.Rect ();
            sep.init (NAME_X, h - 1, w - PAD - NAME_X, 1);
            s.append_color (sep_fg, sep);
        }
    }

    // Minimal padlock: rounded body + a stroked shackle, all GSK.
    static void draw_lock (Gtk.Snapshot s, float x, float y, float sz, Gdk.RGBA c) {
        float bh = sz * 0.60f;
        float by = y + sz - bh;

        var body = Graphene.Rect ();
        body.init (x, by, sz, bh);
        var rr = Gsk.RoundedRect ();
        rr.init_from_rect (body, sz * 0.18f);
        s.push_rounded_clip (rr);
        s.append_color (c, body);
        s.pop ();

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
