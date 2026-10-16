public class Banner : Gtk.Box {

    public uint32 id;
    public signal void action_invoked(string key);
    public signal void dismissed();

    private Gtk.Image      icon_img;
    private Gtk.Label      title_lbl;
    private Gtk.Label      body_lbl;
    private Gtk.Box        actions_row;
    private bool           has_default = false;
    private string[]       current_actions = {};

    public Banner(Notification n) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: Theme.spacing);

        id = n.id;

        set_size_request(Theme.width, -1);

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
        // their own click first) → invoke "default" if offered, else dismiss.
        var click = new Gtk.GestureClick();
        click.set_button(Gdk.BUTTON_PRIMARY);
        click.released.connect((n_press, x, y) => {
            if (has_default) action_invoked("default");
            else dismissed();
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
        // body_to_markup always yields balanced, escaped markup.
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

        bool has_actions = false;
        has_default = false;
        // actions[] is pairs of [key, label]. The special "default" key is
        // the whole-banner click, not a button.
        for (int i = 0; i + 1 < actions.length; i += 2) {
            string key   = actions[i];
            string label = actions[i + 1];
            if (key == "default") { has_default = true; continue; }
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
}
