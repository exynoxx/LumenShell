using Gtk;

// One device cell inside a grouped .cc-card. Leading device-type glyph, name,
// trailing blue check when connected. RSSI is unreliable for paired devices, so
// there's no signal glyph. Selection fill + inset separator, all GSK.
public class BluetoothRow : Gtk.Widget {

    public const int ROW_H = 44;
    const int PAD    = 16;
    const int NAME_X = PAD + 28;

    public string mac          { get; private set; }
    public string dev_name     { get; private set; }
    public bool   is_paired    { get; private set; }
    public bool   is_connected { get; set; }
    public bool   selected     { get; set; }
    public bool   show_separator { get; set; default = true; }

    public signal void activated ();

    string glyph;
    bool hovered = false;

    static Gdk.RGBA sel_fill = Utils.rgba (0.039f, 0.518f, 1.0f, 0.18f);
    static Gdk.RGBA hov_fill = Utils.rgba (1f, 1f, 1f, 0.06f);
    static Gdk.RGBA name_fg  = Utils.rgba (1f, 1f, 1f, 1f);
    static Gdk.RGBA dim_fg   = Utils.rgba (0.921f, 0.921f, 0.960f, 0.55f);
    static Gdk.RGBA sep_fg   = Utils.rgba (1f, 1f, 1f, 0.10f);

    public BluetoothRow (BtDevice dev) {
        this.mac          = dev.mac;
        this.dev_name     = dev.name;
        this.is_paired    = dev.paired;
        this.is_connected = dev.connected;
        this.glyph        = glyph_for (dev.dev_icon);

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

        var glyph_layout = create_pango_layout (glyph);
        var ga = new Pango.AttrList ();
        ga.insert (Pango.AttrSize.new_absolute (15 * Pango.SCALE));
        glyph_layout.set_attributes (ga);
        int gw, gh;
        glyph_layout.get_pixel_size (out gw, out gh);
        var gp = Graphene.Point ();
        gp.init (PAD, (h - gh) / 2);
        s.save (); s.translate (gp);
        s.append_layout (glyph_layout, is_connected ? name_fg : dim_fg);
        s.restore ();

        var layout = create_pango_layout (dev_name);
        var attrs = new Pango.AttrList ();
        attrs.insert (Pango.AttrSize.new_absolute (15 * Pango.SCALE));
        attrs.insert (Pango.attr_weight_new (Pango.Weight.MEDIUM));
        layout.set_attributes (attrs);
        layout.set_width ((w - NAME_X - (PAD + 24)) * Pango.SCALE);
        layout.set_ellipsize (Pango.EllipsizeMode.END);
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        var pt = Graphene.Point ();
        pt.init (NAME_X, (h - th) / 2);
        s.save (); s.translate (pt);
        s.append_layout (layout, (is_connected || is_paired) ? name_fg : dim_fg);
        s.restore ();

        if (is_connected) {
            var check = create_pango_layout ("✓");
            var ca = new Pango.AttrList ();
            ca.insert (Pango.AttrSize.new_absolute (15 * Pango.SCALE));
            ca.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
            check.set_attributes (ca);
            int cw, ch;
            check.get_pixel_size (out cw, out ch);
            var cp = Graphene.Point ();
            cp.init (w - PAD - cw, (h - ch) / 2);
            s.save (); s.translate (cp);
            s.append_layout (check, CcStyle.accent);
            s.restore ();
        }

        if (show_separator) {
            var sep = Graphene.Rect ();
            sep.init (NAME_X, h - 1, w - PAD - NAME_X, 1);
            s.append_color (sep_fg, sep);
        }
    }
}
