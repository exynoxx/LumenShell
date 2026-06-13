using Gtk;

public class Banner : Gtk.Box {

    public uint32 id;
    public signal void action_invoked(string key);
    public signal void dismissed();
    public signal void leave_finished();

    private Gtk.Image      icon_img;
    private Gtk.Label      title_lbl;
    private Gtk.Label      body_lbl;
    private Gtk.Box        actions_row;
    private bool           has_actions = false;
    private string[]       current_actions = {};

    private bool         leaving = false;
    private DismissStyle leave_style = DismissStyle.SLIDE_RIGHT;
    private int64        leave_started_us = 0;
    private double       leave_progress = 0.0;
    private int          full_natural_h = -1;
    private uint         leave_tick_id = 0;

    public Banner(Notification n) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: Theme.spacing);

        id = n.id;

        set_size_request(Theme.width, -1);
        margin_top    = 0;
        margin_bottom = 0;

        var top_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, Theme.spacing);
        top_row.margin_start  = Theme.padding;
        top_row.margin_end    = Theme.padding;
        top_row.margin_top    = Theme.padding;
        top_row.margin_bottom = Theme.padding;

        icon_img = new Gtk.Image();
        icon_img.pixel_size = 32;
        icon_img.set_valign(Gtk.Align.START);
        top_row.append(icon_img);

        var text_col = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        text_col.set_hexpand(true);

        title_lbl = new Gtk.Label("");
        title_lbl.set_xalign(0);
        title_lbl.set_halign(Gtk.Align.START);
        title_lbl.add_css_class("lumen-notif-title");
        title_lbl.set_wrap(true);
        title_lbl.set_wrap_mode(Pango.WrapMode.WORD_CHAR);
        title_lbl.set_max_width_chars(40);
        text_col.append(title_lbl);

        body_lbl = new Gtk.Label("");
        body_lbl.set_xalign(0);
        body_lbl.set_halign(Gtk.Align.START);
        body_lbl.set_wrap(true);
        body_lbl.set_wrap_mode(Pango.WrapMode.WORD_CHAR);
        body_lbl.set_max_width_chars(40);
        body_lbl.add_css_class("lumen-notif-body");
        text_col.append(body_lbl);

        top_row.append(text_col);
        append(top_row);

        actions_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        actions_row.set_halign(Gtk.Align.FILL);
        actions_row.set_hexpand(true);
        actions_row.set_homogeneous(true);
        actions_row.add_css_class("lumen-notif-actions");
        actions_row.set_visible(false);
        append(actions_row);

        update_from(n);

        // Click anywhere on the card (except on a button — buttons consume
        // their own click first) → dismiss.
        var click = new Gtk.GestureClick();
        click.set_button(Gdk.BUTTON_PRIMARY);
        click.released.connect((n_press, x, y) => {
            dismissed();
        });
        add_controller(click);
    }

    public void update_from(Notification n) {
        title_lbl.set_text(n.summary);
        set_body_markup(n.body);
        body_lbl.set_visible(n.body != "");

        set_icon(n);
        rebuild_actions(n.actions);

        queue_draw();
    }

    private void set_body_markup(string body) {
        // body_to_markup yields balanced, escaped GtkLabel markup, so
        // set_markup accepts it (note: GtkLabel's <a> support means we can't
        // pre-validate with Pango.parse_markup, which rejects <a>).
        body_lbl.set_markup(Utils.body_to_markup(body));
    }

    private void set_icon(Notification n) {
        string? src = (n.image_path != null && (!) n.image_path != "")
                      ? n.image_path
                      : n.app_icon;
        if (src == null || (!) src == "") {
            icon_img.set_visible(false);
            return;
        }
        icon_img.set_visible(true);
        string s = (!) src;
        string? file_path = null;
        if (s.has_prefix("/"))            file_path = s;
        else if (s.has_prefix("file://")) file_path = s.substring(7);

        if (file_path != null) {
            if (FileUtils.test((!) file_path, FileTest.EXISTS)) {
                icon_img.set_from_file((!) file_path);
            } else {
                warning("lumen-notifications: icon file missing: %s", (!) file_path);
                icon_img.set_from_icon_name("dialog-information");
            }
        } else {
            icon_img.set_from_icon_name(s);
        }
    }

    private void rebuild_actions(string[] actions) {
        if (actions_equal(actions, current_actions)) return;

        Gtk.Widget? child = actions_row.get_first_child();
        while (child != null) {
            var next = ((!) child).get_next_sibling();
            actions_row.remove((!) child);
            child = next;
        }

        has_actions = false;
        // actions[] is pairs of [key, label]. Skip the special "default"
        // key (whole-banner click already dismisses with action).
        for (int i = 0; i + 1 < actions.length; i += 2) {
            string key   = actions[i];
            string label = actions[i + 1];
            if (key == "default") continue;
            var btn = new Gtk.Button.with_label(label);
            btn.add_css_class("lumen-notif-action");
            btn.set_hexpand(true);
            btn.set_halign(Gtk.Align.FILL);
            btn.clicked.connect(() => {
                action_invoked(key);
            });
            actions_row.append(btn);
            has_actions = true;
        }
        actions_row.set_visible(has_actions);
        current_actions = actions;
    }

    private static bool actions_equal(string[] a, string[] b) {
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    public override void snapshot(Gtk.Snapshot s) {
        if (!leaving) {
            draw_card(s);
            return;
        }

        double opacity = 1.0 - leave_progress;
        if (opacity < 0.0) opacity = 0.0;

        s.save();
        s.push_opacity(opacity);

        if (leave_style == DismissStyle.SLIDE_RIGHT) {
            float dx = (float) (leave_progress * (Theme.width + Theme.slide_px * 2));
            var p = Graphene.Point();
            p.x = dx; p.y = 0f;
            s.translate(p);
        }

        draw_card(s);

        s.pop();      // pop_opacity
        s.restore();  // restore transform
    }

    private void draw_card(Gtk.Snapshot s) {
        int   w = get_width();
        int   h = get_height();
        if (w <= 0 || h <= 0) return;

        float r = (float) Theme.radius;

        var rect = Graphene.Rect();
        rect.init(0f, 0f, (float) w, (float) h);

        var rr = Gsk.RoundedRect();
        rr.init_from_rect(rect, r);

        s.push_rounded_clip(rr);

        s.append_color(Theme.banner_bg, rect);

        float[] border_w = { 1f, 1f, 1f, 1f };
        Gdk.RGBA[] border_c = {
            Theme.banner_border, Theme.banner_border,
            Theme.banner_border, Theme.banner_border
        };
        s.append_border(rr, border_w, border_c);

        base.snapshot(s);

        s.pop();
    }

    public override void measure(Gtk.Orientation orientation,
                                 int             for_size,
                                 out int         minimum,
                                 out int         natural,
                                 out int         minimum_baseline,
                                 out int         natural_baseline) {
        base.measure(orientation, for_size,
                     out minimum, out natural,
                     out minimum_baseline, out natural_baseline);
        if (leaving && orientation == Gtk.Orientation.VERTICAL) {
            if (full_natural_h < 0) full_natural_h = natural;
            double remaining = 1.0 - leave_progress;
            if (remaining < 0.0) remaining = 0.0;
            int h = (int) Math.round(full_natural_h * remaining);
            natural = h;
            if (minimum > h) minimum = h;
        }
    }

    public void begin_leave(DismissStyle style) {
        if (leaving) return;
        leaving = true;
        leave_style = style;
        leave_progress = 0.0;
        // Capture pre-shrink natural height so we have a stable target.
        int min, nat, mb, nb;
        base.measure(Gtk.Orientation.VERTICAL, Theme.width,
                     out min, out nat, out mb, out nb);
        full_natural_h = nat;

        // Buttons should stop responding once the leave starts.
        actions_row.set_sensitive(false);

        // begin_leave only runs after the widget is realized, so frame_clock
        // is guaranteed non-null. Using monotonic_time as a fallback would
        // mix time bases with clock.get_frame_time() below.
        leave_started_us = ((!) get_frame_clock()).get_frame_time();

        leave_tick_id = add_tick_callback((widget, clock) => {
            int64 now = clock.get_frame_time();
            double elapsed_ms = (now - leave_started_us) / 1000.0;
            int duration = Theme.fade_out_ms > 0 ? Theme.fade_out_ms : 200;
            double t = elapsed_ms / duration;
            if (t >= 1.0) {
                leave_progress = 1.0;
                queue_resize();
                queue_draw();
                leave_finished();
                leave_tick_id = 0;
                return Source.REMOVE;
            }
            leave_progress = ease_out_cubic(t);
            queue_resize();
            queue_draw();
            return Source.CONTINUE;
        });
    }

    private static double ease_out_cubic(double t) {
        double inv = 1.0 - t;
        return 1.0 - inv * inv * inv;
    }
}
