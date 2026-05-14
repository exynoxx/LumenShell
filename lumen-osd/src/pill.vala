using Gtk;

public class Pill : Gtk.Box {

    public Gtk.Image     icon     = new Gtk.Image();
    public ProgressTrack progress = new ProgressTrack();
    public Gtk.Label     label    = new Gtk.Label("");

    public Pill() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);

        margin_start  = 20;
        margin_end    = 20;
        margin_top    = 12;
        margin_bottom = 12;

        icon.pixel_size = 24;
        icon.set_from_icon_name("audio-volume-medium-symbolic");
        append(icon);

        progress.set_hexpand(true);
        progress.set_valign(Gtk.Align.CENTER);
        append(progress);

        label.set_valign(Gtk.Align.CENTER);
        label.set_visible(false);
        append(label);

        set_size_request(Theme.width, Theme.height);
    }

    /** Show as a slider: icon + progress + (value%) label. */
    public void show_slider(string icon_name, double fraction, string text) {
        icon.set_from_icon_name(icon_name);
        progress.fraction = fraction;
        progress.set_visible(true);
        label.set_text(text);
        label.set_visible(text != "");
    }

    /** Show as a chip: icon + label, no bar. */
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
            minimum = natural = 8;
        }
        minimum_baseline = -1;
        natural_baseline = -1;
    }

    public override void snapshot(Gtk.Snapshot s) {
        int   w       = get_width();
        int   h       = get_height();
        float track_h = 6f;
        float track_y = (h - track_h) * 0.5f;

        var track_rect = Graphene.Rect();
        track_rect.init(0f, track_y, (float) w, track_h);
        var trr = Gsk.RoundedRect();
        trr.init_from_rect(track_rect, track_h * 0.5f);
        s.push_rounded_clip(trr);
        s.append_color(Theme.progress_track, track_rect);
        s.pop();

        float fill_w = (float) (w * _fraction);
        if (fill_w <= 0f) return;

        var fill_rect = Graphene.Rect();
        fill_rect.init(0f, track_y, fill_w, track_h);
        var frr = Gsk.RoundedRect();
        frr.init_from_rect(fill_rect, track_h * 0.5f);
        s.push_rounded_clip(frr);
        s.append_color(Theme.progress_fill, fill_rect);
        s.pop();
    }
}
