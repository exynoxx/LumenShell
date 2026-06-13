using Gtk;

public class Pill : Gtk.Box {

    public Gtk.Image     icon     = new Gtk.Image();
    public ProgressTrack progress = new ProgressTrack();
    public Gtk.Label     label    = new Gtk.Label("");

    private Gtk.Box inner;

    public Pill() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

        // The Pill itself spans the full background (with rounded corners).
        // Content lives inside `inner`, whose margins act as internal padding
        // so the icon/bar/label never touch the curved edge.
        inner = new Gtk.Box(Gtk.Orientation.HORIZONTAL, Theme.content_spacing);
        inner.margin_start  = Theme.padding_x;
        inner.margin_end    = Theme.padding_x;
        inner.margin_top    = Theme.padding_y;
        inner.margin_bottom = Theme.padding_y;
        inner.set_hexpand(true);
        inner.set_vexpand(true);

        icon.pixel_size = 22;
        icon.set_from_icon_name("audio-volume-medium-symbolic");
        icon.set_valign(Gtk.Align.CENTER);
        inner.append(icon);

        progress.set_hexpand(true);
        progress.set_valign(Gtk.Align.CENTER);
        inner.append(progress);

        label.set_valign(Gtk.Align.CENTER);
        label.set_visible(false);
        inner.append(label);

        append(inner);

        set_size_request(Theme.width, Theme.height);
    }

    public void show_slider(string icon_name, double fraction, string text) {
        icon.set_from_icon_name(icon_name);
        progress.fraction = fraction;
        progress.set_visible(true);
        label.set_text(text);
        label.set_visible(text != "");
    }

    public void show_chip(string icon_name, string text) {
        icon.set_from_icon_name(icon_name);
        progress.set_visible(false);
        label.set_text(text);
        label.set_visible(true);
    }

    public override void snapshot(Gtk.Snapshot s) {
        int   w      = get_width();
        int   h      = get_height();
        float radius = Theme.corner_radius < 0
                       ? h * 0.5f
                       : (float) Theme.corner_radius;

        var bg_rect = Graphene.Rect();
        bg_rect.init(0f, 0f, (float) w, (float) h);

        var rr = Gsk.RoundedRect();
        rr.init_from_rect(bg_rect, radius);

        s.push_rounded_clip(rr);
        s.append_color(Theme.background, bg_rect);
        s.pop();

        base.snapshot(s);
    }
}

public class ProgressTrack : Gtk.Widget {

    private double _fraction = 0.0;
    public double fraction {
        get { return _fraction; }
        set {
            double v = value;
            if (v < 0.0) v = 0.0;
            if (v > 1.0) v = 1.0;
            _fraction = v;
            queue_draw();
        }
    }

    public override void measure(Gtk.Orientation orientation,
                                 int             for_size,
                                 out int         minimum,
                                 out int         natural,
                                 out int         minimum_baseline,
                                 out int         natural_baseline) {
        if (orientation == Gtk.Orientation.HORIZONTAL) {
            minimum = 80;
            natural = 200;
        } else {
            minimum = natural = 6;
        }
        minimum_baseline = -1;
        natural_baseline = -1;
    }

    public override void snapshot(Gtk.Snapshot s) {
        int   w       = get_width();
        int   h       = get_height();
        float track_h = (float) h;
        float track_y = 0f;

        var track_rect = Graphene.Rect();
        track_rect.init(0f, track_y, (float) w, track_h);
        var trr = Gsk.RoundedRect();
        trr.init_from_rect(track_rect, track_h * 0.5f);
        s.push_rounded_clip(trr);
        s.append_color(Theme.progress_track, track_rect);
        s.pop();

        float fill_w = (float) (w * _fraction);
        if (fill_w <= 0f) return;
        // Ensure the rounded fill cap is visible even at tiny fractions.
        if (fill_w < track_h) fill_w = track_h;

        var fill_rect = Graphene.Rect();
        fill_rect.init(0f, track_y, fill_w, track_h);
        var frr = Gsk.RoundedRect();
        frr.init_from_rect(fill_rect, track_h * 0.5f);
        s.push_rounded_clip(frr);
        s.append_color(Theme.progress_fill, fill_rect);
        s.pop();
    }
}
