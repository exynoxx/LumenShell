// lumen-corner: bottom-left hot-corner launcher. Pointer near the corner
// slides out a ring-quarter (annular sector) holding 4 app icons.
//
// Usage: lumen-corner [app.desktop ...]   (first 4 that exist are used)

// Ring geometry; medium defaults, overridden by [style] size= in corner.ini.
int OUTER = 240;            // outer arc radius (px)
int INNER = 140;            // inner arc radius — the transparent hole
const int HOT   = 40;       // closed-state trigger zone (px square in the corner, above the panel)
const int SLACK = 24;       // how far past the outer arc before it closes
int ICON  = 40;
const double SPEED = 6.0;   // full open/close takes 1/SPEED s

const string[] DEFAULT_APPS = {
    "org.gnome.Nautilus.desktop", "firefox.desktop",
    "org.gnome.Terminal.desktop", "org.gnome.Settings.desktop",
    "org.gnome.Ptyxis.desktop", "kitty.desktop", "foot.desktop",
};

class Corner : Gtk.Widget {
    public AppInfo[] apps;
    public Gdk.RGBA bg;
    public double t = 0;        // animation progress 0..1
    public bool open = false;
    public int hover = -1;
    int64 last_us = 0;

    public signal void open_changed();

    public void set_open(bool v) {
        if (open == v) return;
        open = v;
        if (!v) hover = -1;
        open_changed();
        last_us = 0;
        add_tick_callback((w, clock) => {
            int64 now = clock.get_frame_time();
            double dt = last_us == 0 ? 0 : (now - last_us) / 1e6;
            last_us = now;
            t = (t + (open ? dt : -dt) * SPEED).clamp(0, 1);
            queue_draw();
            return open ? t < 1 : t > 0;
        });
    }

    // Sector index under (x, y) in widget coords, or -1.
    public int sector_at(double x, double y) {
        double dx = x, dy = get_height() - y;
        double r = Math.hypot(dx, dy);
        if (r < INNER || r > OUTER || dx < 0 || dy < 0) return -1;
        double a = Math.atan2(dy, dx);  // 0 = right, π/2 = up
        return ((int)(a / (Math.PI / 2) * apps.length)).clamp(0, apps.length - 1);
    }

    static void ring_path(Cairo.Context cr, int h, double a0, double a1) {
        cr.new_path();
        cr.arc(0, h, OUTER, a0, a1);
        cr.arc_negative(0, h, INNER, a1, a0);
        cr.close_path();
    }

    public override void snapshot(Gtk.Snapshot s) {
        // Always emit a node: with an empty frame GTK never attaches a buffer,
        // so the layer surface never maps and never gets pointer input.
        s.append_color({ 0, 0, 0, 0 }, { { 0, 0 }, { 1, 1 } });
        if (t <= 0 || apps.length == 0) return;
        double e = 1 - Math.pow(1 - t, 3);  // ease-out cubic
        int h = get_height();
        // Slide out of the corner, down-left → into place.
        s.translate({ (float)(-(1 - e) * OUTER * 0.5), (float)((1 - e) * OUTER) });

        var cr = s.append_cairo({ { 0, 0 }, { OUTER, h } });
        double seg = (Math.PI / 2) / apps.length;
        // Cairo angles: 0 = right, -π/2 = up; sector i counts from the right.
        // One fill for the whole ring (per-sector fills leave AA seams), hover on top.
        ring_path(cr, h, -Math.PI / 2, 0);
        cr.set_source_rgba(bg.red, bg.green, bg.blue, bg.alpha * e);
        cr.fill();
        if (hover >= 0) {
            ring_path(cr, h, -seg * (hover + 1), -seg * hover);
            cr.set_source_rgba(0.30, 0.45, 0.75, 0.92 * e);
            cr.fill();
        }

        var theme = Gtk.IconTheme.get_for_display(get_display());
        double mid = (OUTER + INNER) / 2.0;
        for (int i = 0; i < apps.length; i++) {
            double a = seg * (i + 0.5);
            float cx = (float)(Math.cos(a) * mid), cy = (float)(h - Math.sin(a) * mid);
            var icon = apps[i].get_icon() ?? new ThemedIcon("application-x-executable");
            var p = theme.lookup_by_gicon(icon, ICON, get_scale_factor(), Gtk.TextDirection.NONE, 0);
            s.save();
            s.translate({ cx - ICON / 2f, cy - ICON / 2f });
            s.push_opacity(e);
            p.snapshot(s, ICON, ICON);
            s.pop();
            s.restore();
        }
    }
}

// ~/.config/lumen-corner/config.ini
//   [style]
//   background=#eee            (default; also "transparent" or "rgba(30,30,35,0.85)")
//   size=medium                (small | medium | large)
// Sets the ring geometry globals and returns the background colour.
Gdk.RGBA load_config() {
    var c = Gdk.RGBA();
    c.parse("#eee");
    var kf = new KeyFile();
    try {
        kf.load_from_file(Environment.get_user_config_dir() + "/lumen-corner/config.ini", KeyFileFlags.NONE);
        if (kf.has_key("style", "size")) {
            switch (kf.get_string("style", "size").strip()) {
            case "small":  OUTER = 180; INNER = 105; ICON = 32; break;
            case "medium": break;
            case "large":  OUTER = 320; INNER = 187; ICON = 52; break;
            default: warning("config.ini: unknown size, using medium"); break;
            }
        }
        if (!kf.has_key("style", "background")) return c;
        var v = kf.get_string("style", "background").strip();
        if (v == "transparent") c = { 0, 0, 0, 0 };  // Gdk.RGBA.parse rejects this keyword
        else if (!c.parse(v)) { warning("config.ini: bad background '%s', using #eee", v); c.parse("#eee"); }
    } catch (Error e) {}  // no file / no key -> default
    return c;
}

void set_region(Gtk.Window win, bool open) {
    int s = open ? OUTER : HOT;
    win.get_surface().set_input_region(new Cairo.Region.rectangle({ 0, OUTER - s, s, s }));
}

int main(string[] args) {
    var app = new Gtk.Application("io.github.LumenCorner", ApplicationFlags.NON_UNIQUE);
    app.activate.connect(() => {
        AppInfo[] apps = {};
        unowned string[] ids = args.length > 1 ? args[1:args.length] : DEFAULT_APPS;
        foreach (var id in ids) {
            var info = new DesktopAppInfo(id);
            if (info != null && apps.length < 4) apps += info;
        }
        if (apps.length == 0) { warning("no launchable apps found"); return; }

        var win = new Gtk.ApplicationWindow(app);
        GtkLayerShell.init_for_window(win);
        GtkLayerShell.set_namespace(win, "lumen-corner");
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, true);
        GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE);

        var css = new Gtk.CssProvider();
        css.load_from_string("window { background: transparent; }");
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        var corner = new Corner() { apps = apps, bg = load_config() };
        corner.set_size_request(OUTER, OUTER);
        win.child = corner;

        // Closed: only a tiny corner square takes input so the rest of the
        // screen stays clickable. Open: the whole OUTER×OUTER square.
        // ponytail: square input region while open, swap for a ring-shaped
        // region if clicks through the inner hole ever matter.
        corner.open_changed.connect(() => set_region(win, corner.open));
        win.map.connect(() => set_region(win, corner.open));

        var motion = new Gtk.EventControllerMotion();
        motion.enter.connect((x, y) => corner.set_open(true));
        motion.motion.connect((x, y) => {
            if (!corner.open) { corner.set_open(true); return; }
            if (Math.hypot(x, OUTER - y) > OUTER + SLACK) { corner.set_open(false); return; }
            int h = corner.sector_at(x, y);
            if (h != corner.hover) { corner.hover = h; corner.queue_draw(); }
        });
        motion.leave.connect(() => corner.set_open(false));
        corner.add_controller(motion);

        var click = new Gtk.GestureClick();
        click.released.connect((n, x, y) => {
            int i = corner.sector_at(x, y);
            if (i < 0) return;
            try {
                apps[i].launch(null, win.get_display().get_app_launch_context());
            } catch (Error e) {
                warning("launch %s: %s", apps[i].get_id(), e.message);
            }
            corner.set_open(false);
        });
        corner.add_controller(click);

        win.present();
        if (Environment.get_variable("LUMEN_CORNER_OPEN") != null) corner.set_open(true);  // screenshots/debug
    });
    return app.run(new string[] { args[0] });
}
