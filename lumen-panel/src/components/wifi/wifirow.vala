using Gtk;

// One scanned-network row. Custom-drawn to match the original UiSignalBars +
// SSID + lock + (optional) disconnect button layout. Hover and selected
// states are drawn directly in snapshot() — no CSS list-row chrome.
public class WifiRow : Gtk.Widget {

    public const int ROW_H = 36;
    const int PAD = 14;

    public string ssid     { get; private set; }
    public int    signal_pct { get; private set; }
    public bool   is_secured { get; private set; }
    public bool   is_connected { get; set; }
    public bool   selected { get; set; }

    public signal void activated ();
    public signal void disconnect_clicked ();

    SignalBars bars;
    Gtk.Button? disc_btn = null;
    bool hovered = false;

    static Gdk.RGBA sel_bg   = rgba(0.10f, 0.24f, 0.62f, 0.88f);
    static Gdk.RGBA hov_bg   = rgba(0.17f, 0.18f, 0.24f, 0.85f);
    static Gdk.RGBA conn_fg  = rgba(0.18f, 0.88f, 0.42f, 1f);
    static Gdk.RGBA norm_fg  = rgba(0.90f, 0.91f, 0.94f, 1f);
    static Gdk.RGBA lock_fg  = rgba(0.52f, 0.52f, 0.58f, 1f);

    static Gdk.RGBA rgba (float r, float g, float b, float a) {
        var c = Gdk.RGBA();
        c.red = r; c.green = g; c.blue = b; c.alpha = a;
        return c;
    }

    public WifiRow (WifiNet net, bool is_connected) {
        this.ssid = net.ssid;
        this.signal_pct = net.signal;
        this.is_secured = net.security != "" && net.security != "--";
        this.is_connected = is_connected;

        height_request = ROW_H;
        hexpand = true;

        bars = new SignalBars(net.signal);
        bars.set_parent(this);

        if (is_connected) {
            disc_btn = new Gtk.Button.with_label("×") {
                width_request = 22,
                height_request = 18,
            };
            disc_btn.add_css_class("lumen-button");
            disc_btn.add_css_class("danger");
            disc_btn.clicked.connect(() => disconnect_clicked());
            disc_btn.set_parent(this);
        }

        var click = new Gtk.GestureClick() { button = Gdk.BUTTON_PRIMARY };
        click.released.connect(() => activated());
        add_controller(click);

        var motion = new Gtk.EventControllerMotion();
        motion.enter.connect(() => { hovered = true;  queue_draw(); });
        motion.leave.connect(() => { hovered = false; queue_draw(); });
        add_controller(motion);
    }

    public override void dispose () {
        if (bars != null)     { bars.unparent();     bars = null; }
        if (disc_btn != null) { disc_btn.unparent(); disc_btn = null; }
        base.dispose();
    }

    public override void size_allocate (int width, int height, int baseline) {
        var t1 = new Gsk.Transform().translate({ PAD, (height - 20) / 2 });
        bars.allocate(25, 20, baseline, t1);

        if (disc_btn != null) {
            int bx = width - PAD - 22;
            int by = (height - 18) / 2;
            var t2 = new Gsk.Transform().translate({ bx, by });
            disc_btn.allocate(22, 18, baseline, t2);
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
            min = 200; nat = 360;
        } else {
            min = nat = ROW_H;
        }
    }

    public override void snapshot (Gtk.Snapshot s) {
        int w = get_width();
        int h = get_height();

        if (selected || hovered) {
            var rect = Graphene.Rect();
            rect.init(6, 3, w - 12, h - 6);
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(rect, 9);
            s.push_rounded_clip(rr);
            s.append_color(selected ? sel_bg : hov_bg, rect);
            s.pop();
        }

        base.snapshot(s);

        var layout = create_pango_layout(ssid);
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.AttrSize.new_absolute(15 * Pango.SCALE));
        attrs.insert(Pango.attr_weight_new(Pango.Weight.MEDIUM));
        layout.set_attributes(attrs);

        int right_reserve = PAD + 14;
        if (is_secured) right_reserve += 18;
        if (disc_btn != null) right_reserve += 30;
        layout.set_width((w - (PAD + 32) - right_reserve) * Pango.SCALE);
        layout.set_ellipsize(Pango.EllipsizeMode.END);

        int tw, th;
        layout.get_pixel_size(out tw, out th);

        var pt = Graphene.Point();
        pt.init(PAD + 32, (h - th) / 2);
        s.save(); s.translate(pt);
        s.append_layout(layout, is_connected ? conn_fg : norm_fg);
        s.restore();

        if (is_secured) {
            int lx = w - PAD - 14;
            if (disc_btn != null) lx -= 30;
            var lock_layout = create_pango_layout("🔒");
            var la = new Pango.AttrList();
            la.insert(Pango.AttrSize.new_absolute(11 * Pango.SCALE));
            lock_layout.set_attributes(la);
            int lw, lh;
            lock_layout.get_pixel_size(out lw, out lh);
            var lp = Graphene.Point();
            lp.init(lx, (h - lh) / 2);
            s.save(); s.translate(lp);
            s.append_layout(lock_layout, lock_fg);
            s.restore();
        }
    }
}
