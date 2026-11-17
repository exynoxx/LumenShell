public class Pill : Gtk.Box {

    public Gtk.Image     icon     = new Gtk.Image();
    public ProgressTrack progress = new ProgressTrack();
    public Gtk.Label     label    = new Gtk.Label("");

    public Pill() {
        Object(orientation: Theme.vertical() ? Gtk.Orientation.VERTICAL
                                             : Gtk.Orientation.HORIZONTAL,
               spacing: 0);

        bool vert = Theme.vertical();

        // padding_x is along the long axis, padding_y across it — they swap
        // when the pill stands up.
        var inner = new Gtk.Box(orientation, Theme.content_spacing);
        inner.margin_start  = inner.margin_end    = vert ? Theme.padding_y : Theme.padding_x;
        inner.margin_top    = inner.margin_bottom = vert ? Theme.padding_x : Theme.padding_y;
        inner.set_hexpand(true);
        inner.set_vexpand(true);

        icon.pixel_size = 22;
        icon.set_from_icon_name("audio-volume-medium-symbolic");
        icon.set_halign(Gtk.Align.CENTER);
        icon.set_valign(Gtk.Align.CENTER);
        inner.append(icon);

        progress.set_hexpand(!vert);
        progress.set_vexpand(vert);
        progress.set_halign(Gtk.Align.CENTER);
        progress.set_valign(Gtk.Align.CENTER);
        inner.append(progress);

        label.set_halign(Gtk.Align.CENTER);
        label.set_valign(Gtk.Align.CENTER);
        label.set_visible(false);
        inner.append(label);

        append(inner);

        // width/height are long-axis/thickness; a vertical pill swaps them.
        set_size_request(vert ? Theme.height : Theme.width,
                         vert ? Theme.width  : Theme.height);
    }

    public void show_slider(string icon_name, double fraction, string text) {
        // GTK4 drops and re-looks-up the icon even for the same name.
        if (icon.icon_name != icon_name) icon.set_from_icon_name(icon_name);
        progress.fraction = fraction;
        progress.set_visible(true);
        label.set_text(text);
        label.set_visible(text != "");
    }

    public void show_chip(string icon_name, string text) {
        if (icon.icon_name != icon_name) icon.set_from_icon_name(icon_name);
        progress.set_visible(false);
        label.set_text(text);
        label.set_visible(true);
    }

    public override void snapshot(Gtk.Snapshot s) {
        int   w      = get_width();
        int   h      = get_height();
        float radius = Theme.corner_radius < 0
                       ? (float) int.min(w, h) * 0.5f
                       : (float) Theme.corner_radius;

        LumenCommon.Draw.fill_rounded(s, 0f, 0f, w, h, radius, Theme.background);

        base.snapshot(s);
    }
}

public class ProgressTrack : Gtk.Widget {

    private double _fraction = 0.0;
    public double fraction {
        get { return _fraction; }
        set {
            _fraction = value.clamp(0.0, 1.0);
            queue_draw();
        }
    }

    public override void measure(Gtk.Orientation orientation,
                                 int             for_size,
                                 out int         minimum,
                                 out int         natural,
                                 out int         minimum_baseline,
                                 out int         natural_baseline) {
        var long_axis = Theme.vertical() ? Gtk.Orientation.VERTICAL
                                         : Gtk.Orientation.HORIZONTAL;
        if (orientation == long_axis) {
            minimum = 80;
            natural = 200;
        } else {
            minimum = natural = 6;
        }
        minimum_baseline = -1;
        natural_baseline = -1;
    }

    public override void snapshot(Gtk.Snapshot s) {
        int   w    = get_width();
        int   h    = get_height();
        bool  vert = Theme.vertical();
        float thickness = vert ? (float) w : (float) h;

        LumenCommon.Draw.fill_rounded(s, 0f, 0f, w, h, thickness * 0.5f, Theme.progress_track);

        float fill = (float) ((vert ? h : w) * _fraction);
        if (fill <= 0f) return;
        // Ensure the rounded fill cap is visible even at tiny fractions.
        if (fill < thickness) fill = thickness;

        if (vert)   // grows upward
            LumenCommon.Draw.fill_rounded(s, 0f, h - fill, w, fill, thickness * 0.5f, Theme.progress_fill);
        else
            LumenCommon.Draw.fill_rounded(s, 0f, 0f, fill, h, thickness * 0.5f, Theme.progress_fill);
    }
}
