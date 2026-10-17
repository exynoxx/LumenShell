public class PanelWindow : Gtk.ApplicationWindow {

    // HIDDEN: auto-hide overlay. PUSH: like HIDDEN, but a Wayfire plugin slides the
    // scene away so the panel reveals into the freed strip.
    public enum Mode { NORMAL, HIDDEN, PUSH }

    TrayBar? tray;                  // null when this panel shows no tray
    Gtk.Box  root;

    Mode mode = Mode.NORMAL;
    // HIDDEN and PUSH share the slide/sliver auto-reveal machinery.
    bool hides { get { return mode != Mode.NORMAL; } }
    bool at_top = false;
    GtkLayerShell.Edge slide_edge = GtkLayerShell.Edge.BOTTOM;
    bool reveal_target = false;
    int current_margin = 0;
    int slide_from_margin = 0;
    int64 slide_start_us = 0;
    uint slide_tick_id = 0;
    uint collapse_timeout_id = 0;
    uint resize_tick_id = 0;
    ulong expanded_handler = 0;     // on the shared tray; dropped in release_tray()
    Cairo.Region? last_region = null;

    public PanelWindow (Gtk.Application app, Gdk.Monitor? monitor,
                        bool is_tray_host, TrayBar? tray) {
        GLib.Object(application: app);
        this.tray = tray;

        add_css_class("lumen-panel");
        set_default_size(-1, App.ICON_ROW_HEIGHT);

        mode = parse_mode(PanelConfig.behavior_mode, PanelConfig.behavior_auto_hide);
        at_top = PanelConfig.at_top;
        slide_edge = at_top ? GtkLayerShell.Edge.TOP : GtkLayerShell.Edge.BOTTOM;

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_namespace(this, "lumen-panel");
        if (monitor != null) GtkLayerShell.set_monitor(this, monitor);
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT,  true);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
        GtkLayerShell.set_anchor(this, slide_edge, true);
        GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);

        if (hides) {
            // Start off-edge with only the sliver showing; in PUSH the plugin frees the strip.
            GtkLayerShell.set_exclusive_zone(this, 0);
            current_margin = App.HIDDEN_MARGIN;
            GtkLayerShell.set_margin(this, slide_edge, App.HIDDEN_MARGIN);
            add_css_class("auto-hide");
        } else {
            GtkLayerShell.set_exclusive_zone(this, App.ICON_ROW_HEIGHT);
        }

        root = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
            hexpand = true, vexpand = true,
            valign = at_top ? Gtk.Align.START : Gtk.Align.END,
        };

        string? only_output = (PanelConfig.per_monitor_apps && monitor != null)
            ? monitor.get_connector() : null;

#if PANEL_PEEK
        if (PanelConfig.show_launcher) root.append(new LauncherButton());
#endif

        var app_bar = new AppBar(only_output, is_tray_host);
        root.append(app_bar);

        if (tray != null) root.append(tray);

        var backdrop = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
            hexpand = true, vexpand = true,
        };
        var strip = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
            hexpand = true, height_request = App.ICON_ROW_HEIGHT,
        };
        strip.add_css_class("panel-strip");
        if (at_top) {
            backdrop.append(strip);
            backdrop.append(new Gtk.Box(Gtk.Orientation.VERTICAL, 0) { vexpand = true });
        } else {
            backdrop.append(new Gtk.Box(Gtk.Orientation.VERTICAL, 0) { vexpand = true });
            backdrop.append(strip);
        }

        var overlay = new Gtk.Overlay();
        overlay.set_child(backdrop);
        overlay.add_overlay(root);
        overlay.set_measure_overlay(root, true);

        set_child(overlay);
        present();

        var esc = new Gtk.EventControllerKey();
        esc.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        esc.key_pressed.connect((keyval, keycode, mods) => {
            if (keyval == Gdk.Key.Escape && tray != null && tray.is_expanded()) {
                tray.collapse();
                return true;
            }
            return false;
        });
        ((Gtk.Widget) this).add_controller(esc);

        this.map.connect(update_input_region);
        if (tray != null) {
            // Track the animation so the input region follows the growing tray bbox.
            expanded_handler = tray.expanded_changed.connect(() => {
                update_input_region();
                start_resize_tracking();
            });
        }

        // contains-pointer on the WINDOW, not the tray: Motion.leave on TrayBar
        // misfires during the reveal animation.
        var win_motion = new Gtk.EventControllerMotion();
        win_motion.notify["contains-pointer"].connect(() => {
            if (win_motion.contains_pointer) {
                cancel_collapse();
                if (hides) set_reveal(true);
                return;
            }
            if ((tray != null && tray.is_expanded()) || hides) schedule_collapse();
        });
        ((Gtk.Widget) this).add_controller(win_motion);
    }

    // Detach the shared TrayBar (held by App) so it survives a window rebuild.
    public void release_tray () {
        if (tray == null) return;
        // The handler's closure holds `this`; left connected, the shared tray would
        // keep every rebuilt-away window (and its AppBar) alive.
        if (expanded_handler != 0) SignalHandler.disconnect(tray, expanded_handler);
        expanded_handler = 0;
        root.remove(tray);
        tray = null;
    }

    // Resolve behavior.mode, falling back to the legacy behavior.auto-hide bool
    // when the key is absent (auto-hide = true → HIDDEN).
    static Mode parse_mode (string? mode_str, bool legacy_auto_hide) {
        if (mode_str != null) {
            switch (mode_str.strip()) {
                case "push":   return Mode.PUSH;
                case "hidden": return Mode.HIDDEN;
                default:       return Mode.NORMAL;
            }
        }
        return legacy_auto_hide ? Mode.HIDDEN : Mode.NORMAL;
    }

    void set_reveal (bool reveal) {
        if (!hides) return;
        if (reveal == reveal_target && slide_tick_id == 0) {
            int settled = reveal ? 0 : App.HIDDEN_MARGIN;
            if (current_margin == settled) return;
        }
        reveal_target = reveal;
#if PANEL_PEEK
        // The compositor slides the scene in sync with our margin slide; no-op
        // without the plugin.
        if (mode == Mode.PUSH) {
            if (reveal) PeekIpc.push_start();
            else        PeekIpc.push_stop();
        }
#endif
        start_slide_tracking();
    }

    void start_slide_tracking () {
        slide_from_margin = current_margin;
        slide_start_us = 0;
        if (slide_tick_id != 0) return;
        slide_tick_id = ((Gtk.Widget) this).add_tick_callback((widget, clock) => {
            int target = reveal_target ? 0 : App.HIDDEN_MARGIN;
            if (slide_start_us == 0) slide_start_us = clock.get_frame_time();
            double t = (double) (clock.get_frame_time() - slide_start_us) / App.REVEAL_ANIM_US;
            if (t >= 1.0) {
                current_margin = target;
                GtkLayerShell.set_margin(this, slide_edge, current_margin);
                update_input_region();
                slide_tick_id = 0;
                return GLib.Source.REMOVE;
            }
            double eased = 1.0 - (1.0 - t) * (1.0 - t);
            current_margin = (int) (slide_from_margin + (target - slide_from_margin) * eased);
            GtkLayerShell.set_margin(this, slide_edge, current_margin);
            update_input_region();
            return GLib.Source.CONTINUE;
        });
    }

    void start_resize_tracking () {
        if (tray == null) return;
        if (resize_tick_id != 0) return;
        resize_tick_id = ((Gtk.Widget) this).add_tick_callback((widget, clock) => {
            update_input_region();
            if (!tray.is_animating()) {
                resize_tick_id = 0;
                return GLib.Source.REMOVE;
            }
            return GLib.Source.CONTINUE;
        });
    }

    void schedule_collapse () {
        if (collapse_timeout_id != 0) return;
        collapse_timeout_id = GLib.Timeout.add(App.COLLAPSE_DELAY_MS, () => {
            collapse_timeout_id = 0;
            if (tray != null && tray.is_expanded()) tray.collapse();
            if (hides && (tray == null || !tray.is_expanded())) set_reveal(false);
            return GLib.Source.REMOVE;
        });
    }

    void cancel_collapse () {
        if (collapse_timeout_id == 0) return;
        GLib.Source.remove(collapse_timeout_id);
        collapse_timeout_id = 0;
    }

    // The surface shrinks back a frame AFTER the collapse animation's last tick, so the
    // region must be recomputed on the real resize — at the bottom the strip's y is
    // derived from the height, and a stale (expanded) height puts it off-surface.
    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate(width, height, baseline);
        update_input_region();
    }

    void update_input_region () {
        var gdk_surface = get_surface();
        if (gdk_surface == null) return;

        int sw = get_width();
        int sh = get_height();
        if (sw <= 0 || sh <= 0) return;

        var region = new Cairo.Region();

        if (hides && slide_tick_id != 0) {
            region.union_rectangle(Cairo.RectangleInt() { x = 0, y = 0, width = sw, height = sh });
            apply_input_region(gdk_surface, region);
            return;
        }
        if (hides && !reveal_target) {
            int hy = at_top ? sh - App.SLIVER_PX : 0;
            region.union_rectangle(Cairo.RectangleInt() { x = 0, y = hy, width = sw, height = App.SLIVER_PX });
            apply_input_region(gdk_surface, region);
            return;
        }

        var strip = Cairo.RectangleInt() {
            x = 0,
            y = at_top ? 0 : sh - App.ICON_ROW_HEIGHT,
            width = sw,
            height = App.ICON_ROW_HEIGHT,
        };
        region.union_rectangle(strip);

        if (tray != null && (tray.is_expanded() || tray.is_animating())) {
            Graphene.Point tp;
            if (tray.compute_point(this, Graphene.Point() { x = 0, y = 0 }, out tp)) {
                int tw = tray.get_width();
                int th = tray.get_height();
                if (tw > 0 && th > 0) {
                    var trect = Cairo.RectangleInt() {
                        x = (int) tp.x, y = (int) tp.y, width = tw, height = th,
                    };
                    region.union_rectangle(trect);
                }
            }
        }

        apply_input_region(gdk_surface, region);
    }

    // Only push on change: per-frame resize tracking would otherwise send identical
    // set_input_region() roundtrips every frame.
    void apply_input_region (Gdk.Surface gdk_surface, Cairo.Region region) {
        if (last_region != null && last_region.equal(region)) return;
        last_region = region.copy();
        gdk_surface.set_input_region(region);
    }
}
