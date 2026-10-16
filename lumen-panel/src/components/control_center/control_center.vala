public class ControlCenter : Gtk.Box {

    const int WIDTH  = 560;
    // Minimum height; with the stack's vhomogeneous sizing the panel keeps one
    // constant height, so sliding to a detail never resizes the surface.
    const int HEIGHT = 560;

    Gtk.Stack stack;
    Gtk.Box   home;
    BrightnessService brightness;    // shared, owned by App
    bool night_light_on = false;
    bool caffeine_on = false;
    LogindBridge logind;
    GLib.HashTable<string, IControlModule> mods =
        new GLib.HashTable<string, IControlModule> (str_hash, str_equal);

    public ControlCenter (Gee.List<IControlModule> modules, LogindBridge logind,
                          BrightnessService brightness) {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.logind = logind;
        this.brightness = brightness;
        add_css_class ("control-center");
        set_size_request (WIDTH, HEIGHT);

        foreach (var m in modules) {
            mods.insert (m.module_id (), m);
            string id = m.module_id ();
            m.open_detail.connect (() => open (id));
        }

        stack = new Gtk.Stack () {
            transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            transition_duration = 240,
            hhomogeneous = true,
            vhomogeneous = true,
        };

        // Not in a ScrolledWindow: its natural height doesn't propagate up and the
        // panel collapses to a few px.
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
        if (power != null) {
            // Dock to the bottom: home is stretched to the tallest page (vhomogeneous).
            var power_tile = power.home_tile ();
            power_tile.vexpand = true;
            power_tile.valign  = Gtk.Align.END;
            home.append (power_tile);
        }
    }

    // Inline, not a module: brightness has no tray icon.
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
        // Connected only while mapped: the service is shared and outlives this CC,
        // so a permanent handler would pin a rebuilt-away tray in memory.
        ulong changed_id = 0;
        slider.map.connect (() => {
            suppress = true;
            slider.set_value (brightness.percent);
            suppress = false;
            changed_id = brightness.changed.connect (() => {
                suppress = true;
                slider.set_value (brightness.percent);
                suppress = false;
            });
        });
        slider.unmap.connect (() => {
            if (changed_id != 0) SignalHandler.disconnect (brightness, changed_id);
            changed_id = 0;
        });
        row.append (slider);

        // Caffeine: a zwp_idle_inhibitor silences ext-idle-notify (auto-lock, DPMS) and a
        // logind idle inhibitor blocks IdleAction suspend. Runtime-only.
        var cup_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        cup_btn.add_css_class ("cc-toggle");
        var cup_img = new Gtk.Image () { pixel_size = 20 };
        cup_img.set_from_resource (CcStyle.icon ("coffee"));
        cup_btn.set_child (cup_img);
        cup_btn.clicked.connect (() => {
            caffeine_on = !caffeine_on;
            if (caffeine_on) cup_btn.add_css_class ("on");
            else             cup_btn.remove_css_class ("on");
            set_caffeine (caffeine_on);
        });
        row.append (cup_btn);

        // Optimistic local state: wayfire-night-light has no state-query verb.
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

    void set_caffeine (bool on) {
        logind.set_idle_inhibited (on);
        var surface = (get_root () as Gtk.Window)?.get_surface () as Gdk.Wayland.Surface;
        if (surface == null) return;
        var display = surface.get_display () as Gdk.Wayland.Display;
        if (WLHooks.idle_inhibit_init (display.get_wl_display ()) != 0) {
            warning ("caffeine: compositor lacks idle-inhibit; lock may still trigger");
            return;
        }
        WLHooks.idle_inhibit_set (surface.get_wl_surface (), on);
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
