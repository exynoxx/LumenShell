// A quarter ring anchored at the widget's bottom-left corner, one sector per slot.
public class Ring : Gtk.Widget {
    const int CLOSE_MARGIN = 24;
    const double ANIMATION_SPEED = 6.0;  // progress per second
    const Gdk.RGBA HOVER_COLOR = { 0.30f, 0.45f, 0.75f, 0.92f };

    public bool is_open { get; private set; default = false; }
    public signal void app_chosen(AppInfo app);

    AppInfo?[] apps;
    Style style;
    double progress = 0;
    int hovered = -1;
    uint tick_id = 0;
    int64 last_frame_us = 0;

    public Ring(AppInfo?[] apps, Style style) {
        this.apps = apps;
        this.style = style;
        set_size_request(style.outer_radius, style.outer_radius);

        var motion = new Gtk.EventControllerMotion();
        motion.enter.connect(() => set_open(true));
        motion.motion.connect(on_motion);
        motion.leave.connect(() => set_open(false));
        add_controller(motion);

        var click = new Gtk.GestureClick();
        click.released.connect((n, x, y) => {
            int i = sector_at(x, y);
            if (i < 0 || apps[i] == null) return;
            app_chosen(apps[i]);
            set_open(false);
        });
        add_controller(click);
    }

    public void set_open(bool open) {
        if (is_open == open) return;
        is_open = open;
        if (!open) hovered = -1;
        if (tick_id == 0) {
            last_frame_us = 0;
            tick_id = add_tick_callback(animate);
        }
    }

    bool animate(Gtk.Widget widget, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time();
        double dt = last_frame_us == 0 ? 0 : (now - last_frame_us) / 1e6;
        last_frame_us = now;
        progress = (progress + (is_open ? dt : -dt) * ANIMATION_SPEED).clamp(0, 1);
        queue_draw();
        bool done = is_open ? progress >= 1 : progress <= 0;
        if (done) tick_id = 0;
        return !done;
    }

    void on_motion(double x, double y) {
        if (!is_open) {
            set_open(true);
            return;
        }
        if (distance_from_corner(x, y) > style.outer_radius + CLOSE_MARGIN) {
            set_open(false);
            return;
        }
        int sector = sector_at(x, y);
        if (sector >= 0 && apps[sector] == null) sector = -1;
        if (sector != hovered) {
            hovered = sector;
            queue_draw();
        }
    }

    double distance_from_corner(double x, double y) {
        return Math.hypot(x, get_height() - y);
    }

    int sector_at(double x, double y) {
        double up = get_height() - y;
        double r = distance_from_corner(x, y);
        if (r < style.inner_radius || r > style.outer_radius || x < 0 || up < 0) return -1;
        double angle = Math.atan2(up, x);
        return ((int)(angle / (Math.PI / 2) * apps.length)).clamp(0, apps.length - 1);
    }

    double sector_angle() {
        return (Math.PI / 2) / apps.length;
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        // An empty frame gets no buffer attached, so the layer surface would
        // never map and never receive the pointer.
        snapshot.append_color({ 0, 0, 0, 0 }, { { 0, 0 }, { 1, 1 } });
        if (progress <= 0) return;

        double eased = 1 - Math.pow(1 - progress, 3);
        int outer = style.outer_radius;
        snapshot.translate({ (float)(-(1 - eased) * outer * 0.5), (float)((1 - eased) * outer) });
        draw_ring(snapshot, eased);
        draw_icons(snapshot, eased);
    }

    void draw_ring(Gtk.Snapshot snapshot, double opacity) {
        int h = get_height();
        var cr = snapshot.append_cairo({ { 0, 0 }, { style.outer_radius, h } });
        // One fill for the whole ring: per-sector fills leave anti-aliasing seams.
        fill_sector(cr, h, 0, Math.PI / 2, style.background, opacity);
        if (hovered >= 0) {
            double a = sector_angle();
            fill_sector(cr, h, a * hovered, a * (hovered + 1), HOVER_COLOR, opacity);
        }
    }

    // Angles measured counter-clockwise from the positive x axis.
    void fill_sector(Cairo.Context cr, int h, double from, double to, Gdk.RGBA color, double opacity) {
        cr.new_path();
        cr.arc(0, h, style.outer_radius, -to, -from);
        cr.arc_negative(0, h, style.inner_radius, -from, -to);
        cr.close_path();
        cr.set_source_rgba(color.red, color.green, color.blue, color.alpha * opacity);
        cr.fill();
    }

    void draw_icons(Gtk.Snapshot snapshot, double opacity) {
        var theme = Gtk.IconTheme.get_for_display(get_display());
        int size = style.icon_size;
        double mid_radius = (style.outer_radius + style.inner_radius) / 2.0;
        for (int i = 0; i < apps.length; i++) {
            if (apps[i] == null) continue;
            double angle = sector_angle() * (i + 0.5);
            float x = (float)(Math.cos(angle) * mid_radius - size / 2.0);
            float y = (float)(get_height() - Math.sin(angle) * mid_radius - size / 2.0);
            var icon = apps[i].get_icon() ?? new ThemedIcon("application-x-executable");
            var paintable = theme.lookup_by_gicon(icon, size, get_scale_factor(), Gtk.TextDirection.NONE, 0);
            snapshot.save();
            snapshot.translate({ x, y });
            snapshot.push_opacity(opacity);
            paintable.snapshot(snapshot, size, size);
            snapshot.pop();
            snapshot.restore();
        }
    }
}
