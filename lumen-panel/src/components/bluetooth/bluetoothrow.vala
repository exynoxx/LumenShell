using Gtk;

// RSSI is unreliable for paired devices, so there's no signal glyph.
public class BluetoothRow : Gtk.Widget, CcRow {

    public const int ROW_H = 44;
    const int PAD    = 16;
    const int NAME_X = PAD + 28;

    public string mac       { get; private set; }
    public string dev_name  { get; private set; }
    public bool   is_paired { get; private set; }

    public string key { get { return mac; } }

    public signal void activated ();

    string glyph;

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

    static Gdk.RGBA dim_fg = Utils.rgba (0.921f, 0.921f, 0.960f, 0.55f);

    public BluetoothRow (BtDevice dev) {
        this.mac           = dev.mac;
        this.dev_name      = dev.name;
        this.is_paired     = dev.paired;
        this._is_connected = dev.connected;
        this.glyph         = glyph_for (dev.dev_icon);

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

        if (_selected || hovered)
            Utils.fill_rounded (s, 0, 0, w, h, 0,
                                _selected ? CcStyle.row_selected : CcStyle.row_hover);

        var glyph_layout = Utils.text_layout (this, glyph, 15);
        int gw, gh;
        glyph_layout.get_pixel_size (out gw, out gh);
        Utils.draw_layout (s, glyph_layout, PAD, (h - gh) / 2,
                           _is_connected ? CcStyle.label : dim_fg);

        var layout = Utils.text_layout (this, dev_name, 15, Pango.Weight.MEDIUM);
        layout.set_width ((w - NAME_X - (PAD + 24)) * Pango.SCALE);
        layout.set_ellipsize (Pango.EllipsizeMode.END);
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        Utils.draw_layout (s, layout, NAME_X, (h - th) / 2,
                           (_is_connected || is_paired) ? CcStyle.label : dim_fg);

        if (_is_connected) {
            var check = Utils.text_layout (this, "✓", 15, Pango.Weight.BOLD);
            int cw, ch;
            check.get_pixel_size (out cw, out ch);
            Utils.draw_layout (s, check, w - PAD - cw, (h - ch) / 2, CcStyle.accent);
        }

        if (_show_separator)
            Utils.fill_rounded (s, NAME_X, h - 1, w - PAD - NAME_X, 1, 0, CcStyle.separator);
    }
}
