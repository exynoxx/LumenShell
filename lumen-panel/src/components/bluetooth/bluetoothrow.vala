using Gtk;

// BT RSSI is unreliable for paired devices, so the left slot shows a
// device-type glyph rather than signal bars.
public class BluetoothRow : Gtk.Widget {

    public const int ROW_H = 36;
    const int PAD = 14;

    public string mac          { get; private set; }
    public string dev_name     { get; private set; }
    public bool   is_paired    { get; private set; }
    public bool   is_connected { get; set; }
    public bool   selected     { get; set; }

    public signal void activated ();
    public signal void disconnect_clicked ();

    string glyph;
    Gtk.Button? disc_btn = null;
    bool hovered = false;

    static Gdk.RGBA sel_bg  = Utils.rgba(0.10f, 0.24f, 0.62f, 0.88f);
    static Gdk.RGBA hov_bg  = Utils.rgba(0.17f, 0.18f, 0.24f, 0.85f);
    static Gdk.RGBA conn_fg = Utils.rgba(0.18f, 0.88f, 0.42f, 1f);
    static Gdk.RGBA norm_fg = Utils.rgba(0.90f, 0.91f, 0.94f, 1f);
    static Gdk.RGBA dim_fg  = Utils.rgba(0.62f, 0.63f, 0.68f, 1f);

    public BluetoothRow (BtDevice dev) {
        this.mac          = dev.mac;
        this.dev_name     = dev.name;
        this.is_paired    = dev.paired;
        this.is_connected = dev.connected;
        this.glyph        = glyph_for(dev.dev_icon);

        height_request = ROW_H;
        hexpand = true;

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

    static string glyph_for (string dev_icon) {
        switch (dev_icon) {
            case "audio-card":
            case "audio-headset":
            case "audio-headphones": return "🎧";
            case "input-mouse":      return "🖱";
            case "input-keyboard":   return "⌨";
            case "input-gaming":     return "🎮";
            case "phone":            return "📱";
            case "computer":         return "💻";
            case "video-display":    return "🖥";
            case "printer":          return "🖨";
            default:                 return "🔵";
        }
    }

    public override void dispose () {
        if (disc_btn != null) { disc_btn.unparent(); disc_btn = null; }
        base.dispose();
    }

    public override void size_allocate (int width, int height, int baseline) {
        if (disc_btn != null) {
            int bx = width - PAD - 22;
            int by = (height - 18) / 2;
            var t = new Gsk.Transform().translate({ bx, by });
            disc_btn.allocate(22, 18, baseline, t);
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

        var glyph_layout = create_pango_layout(glyph);
        var ga = new Pango.AttrList();
        ga.insert(Pango.AttrSize.new_absolute(14 * Pango.SCALE));
        glyph_layout.set_attributes(ga);
        int gw, gh;
        glyph_layout.get_pixel_size(out gw, out gh);
        var gp = Graphene.Point();
        gp.init(PAD, (h - gh) / 2);
        s.save(); s.translate(gp);
        s.append_layout(glyph_layout, is_connected ? conn_fg : norm_fg);
        s.restore();

        var layout = create_pango_layout(dev_name);
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.AttrSize.new_absolute(15 * Pango.SCALE));
        attrs.insert(Pango.attr_weight_new(Pango.Weight.MEDIUM));
        layout.set_attributes(attrs);

        int right_reserve = PAD;
        if (disc_btn != null) right_reserve += 30;
        layout.set_width((w - (PAD + 32) - right_reserve) * Pango.SCALE);
        layout.set_ellipsize(Pango.EllipsizeMode.END);

        int tw, th;
        layout.get_pixel_size(out tw, out th);

        Gdk.RGBA fg = is_connected ? conn_fg : (is_paired ? norm_fg : dim_fg);
        var pt = Graphene.Point();
        pt.init(PAD + 32, (h - th) / 2);
        s.save(); s.translate(pt);
        s.append_layout(layout, fg);
        s.restore();
    }
}
