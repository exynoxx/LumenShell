using Gtk;

// The single expanded panel (macOS Control Center). A wide rounded surface with
// an overview of round toggles + info tiles, and an internal stack that slides
// to a module's inline detail (Wi-Fi / Bluetooth network lists). The compact
// icon row above it is untouched — only this expanded area is new.
public class ControlCenter : Gtk.Box {

    const int WIDTH  = 560;
    // Minimum expanded height — combined with the stack's vhomogeneous sizing it
    // gives the whole panel one constant, roomy height regardless of the page.
    const int HEIGHT = 560;

    Gtk.Stack stack;
    Gtk.Box   home;
    BrightnessService brightness = new BrightnessService ();
    bool night_light_on = false;
    GLib.HashTable<string, IControlModule> mods =
        new GLib.HashTable<string, IControlModule> (str_hash, str_equal);

    public ControlCenter (Gee.List<IControlModule> modules) {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class ("control-center");
        set_size_request (WIDTH, HEIGHT);

        foreach (var m in modules) {
            mods.insert (m.module_id (), m);
            string id = m.module_id ();
            m.open_detail.connect (() => open (id));
        }

        // vhomogeneous: every page is sized to the tallest one, so the expanded
        // panel keeps one constant height — sliding to the Wi-Fi/Bluetooth
        // detail no longer grows or shrinks the surface.
        stack = new Gtk.Stack () {
            transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            transition_duration = 240,
            hhomogeneous = true,
            vhomogeneous = true,
        };

        // Added directly (not wrapped in a ScrolledWindow): the overview is
        // short, and a ScrolledWindow's natural height doesn't propagate up to
        // the revealer, which collapsed the panel to a few px.
        home = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_start = 18, margin_end = 18, margin_top = 16, margin_bottom = 18,
        };
        stack.add_named (home, "home");

        build_home ();
        attach_details (modules);

        append (stack);
        stack.visible_child_name = "home";
    }

    void build_home () {
        // Connectivity: Wi-Fi + Bluetooth as compact tiles side by side.
        var wifi = mods.lookup ("wifi");
        var bt   = mods.lookup ("bluetooth");
        if (wifi != null && bt != null) {
            var pair = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { homogeneous = true };
            pair.append (wrap_card (wifi.home_tile ()));
            pair.append (wrap_card (bt.home_tile ()));
            home.append (pair);
        } else if (wifi != null) {
            home.append (wrap_card (wifi.home_tile ()));
        } else if (bt != null) {
            home.append (wrap_card (bt.home_tile ()));
        }

        if (brightness.available) home.append (wrap_card (build_brightness_tile ()));

        var sound = mods.lookup ("sound");
        if (sound != null) home.append (wrap_card (sound.home_tile ()));

        var battery = mods.lookup ("battery");
        if (battery != null) home.append (wrap_card (battery.home_tile ()));

        var power = mods.lookup ("exit");
        if (power != null) home.append (power.home_tile ());
    }

    // Display brightness: a sun glyph + the macOS slider. No detail view —
    // built inline (brightness has no compact-row tray icon, so it isn't a
    // module). brightnessctl carries the write; sysfs polling tracks hotkeys.
    Gtk.Widget build_brightness_tile () {
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
            margin_start = 12, margin_end = 14, margin_top = 8, margin_bottom = 8,
        };
        var icon = new Gtk.Image () { pixel_size = 20, valign = Gtk.Align.CENTER };
        icon.set_from_resource (CcStyle.icon ("brightness"));
        row.append (icon);

        var slider = new CcSlider () { valign = Gtk.Align.CENTER, hexpand = true };
        bool suppress = false;
        slider.set_value (brightness.percent);
        slider.value_changed.connect ((pct) => {
            if (suppress) return;
            brightness.set_level (pct);
        });
        brightness.changed.connect (() => {
            suppress = true;
            slider.set_value (brightness.percent);
            suppress = false;
        });
        row.append (slider);

        // Night-light toggle (warm screen tint) — a round moon button pinned to
        // the right of the brightness slider. Drives the wayfire-night-light
        // plugin over IPC; state is session-local and optimistic (the plugin has
        // no state-query verb). Visual lit state reuses the .cc-toggle / .on look.
        var moon_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        moon_btn.add_css_class ("cc-toggle");
        var moon_img = new Gtk.Image () { pixel_size = 20 };
        moon_img.set_from_resource (CcStyle.icon ("moon"));
        moon_btn.set_child (moon_img);
        moon_btn.clicked.connect (() => {
            night_light_on = !night_light_on;
            if (night_light_on) moon_btn.add_css_class ("on");
            else                moon_btn.remove_css_class ("on");
#if PANEL_PEEK
            PeekIpc.night_light_toggle ();
#endif
        });
        row.append (moon_btn);
        return row;
    }

    void attach_details (Gee.List<IControlModule> modules) {
        foreach (var m in modules) {
            var d = m.detail_view ();
            if (d == null) continue;
            stack.add_named (d, "detail:" + m.module_id ());
            var cd = d as CcDetail;
            if (cd != null) cd.back_requested.connect (show_home);
        }
    }

    Gtk.Widget wrap_card (Gtk.Widget child) {
        var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        card.add_css_class ("cc-card");
        card.append (child);
        return card;
    }

    // Open a module: slide to its detail if it has one, else stay on the
    // overview (where its tile lives inline).
    public void open (string id) {
        var m = mods.lookup (id);
        if (m != null && m.detail_view () != null)
            stack.visible_child_name = "detail:" + id;
        else
            show_home ();
    }

    public void show_home () {
        stack.visible_child_name = "home";
    }
}
