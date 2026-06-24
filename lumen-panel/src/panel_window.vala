using Gtk;

// One panel surface. In single-monitor mode there is exactly one (monitor =
// null); in multi-monitor mode App builds one per Gdk.Monitor, each pinned to
// its output via gtk_layer_set_monitor. Only the tray-host (primary) window
// carries the system tray — the SNI watcher owns a single DBus name and must
// exist exactly once, so secondary panels show the AppBar alone.
public class PanelWindow : Gtk.ApplicationWindow {

    // NORMAL: always visible, reserves an exclusive zone.
    // HIDDEN: auto-hide overlay — slides off the edge, reveals over windows.
    // PUSH:   like HIDDEN, but a Wayfire plugin slides the whole scene
    //         (wallpaper + windows) away from the edge so the panel reveals
    //         into the freed strip instead of overlapping anything.
    public enum Mode { NORMAL, HIDDEN, PUSH }

    TrayBar? tray;                  // null on non-host windows
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

    public PanelWindow (Gtk.Application app, Gdk.Monitor? monitor,
                        bool is_tray_host, TrayBar? tray) {
        GLib.Object(application: app);
        this.tray = tray;

        add_css_class("lumen-panel");
        set_default_size(-1, 60);

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
            // Both HIDDEN and PUSH start off-edge with only the sliver showing
            // and reserve no space; in PUSH the scene-push plugin frees the
            // strip the panel reveals into.
            GtkLayerShell.set_exclusive_zone(this, 0);
            current_margin = App.HIDDEN_MARGIN;
            GtkLayerShell.set_margin(this, slide_edge, App.HIDDEN_MARGIN);
            add_css_class("auto-hide");
        } else {
            GtkLayerShell.set_exclusive_zone(this, 60);
        }

        root = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
            hexpand = true, vexpand = true,
            valign = at_top ? Gtk.Align.START : Gtk.Align.END,
        };

        // Per-monitor app filtering: only filter when per-monitor-apps is on AND
        // this window is pinned to a specific output.
        string? only_output = (PanelConfig.per_monitor_apps && monitor != null)
            ? monitor.get_connector() : null;

#if PANEL_PEEK
        // Persistent launcher button at the very left edge, ahead of the
        // taskbar. Has its own click handler that toggles the app-drawer reveal.
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
            // The tray grows/shrinks the surface every frame while it animates;
            // track that so the input region follows the expanding bbox.
            tray.expanded_changed.connect(() => {
                update_input_region();
                start_resize_tracking();
            });
        }

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

    // Detach the prebuilt primary tray before this window is destroyed so the
    // reused TrayBar widget (held by App) survives the rebuild and can be
    // reattached to the new host window.
    public TrayBar? release_tray () {
        if (tray == null) return null;
        var t = tray;
        root.remove(t);
        tray = null;
        return t;
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
        // PUSH mode: tell the compositor to slide the whole scene away from the
        // edge (reveal) / back (collapse), synchronised with the panel's own
        // margin slide below. No-op if the plugin isn't loaded.
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

    void update_input_region () {
        var gdk_surface = get_surface();
        if (gdk_surface == null) return;

        int sw = get_width();
        int sh = get_height();
        if (sw <= 0 || sh <= 0) return;

        var region = new Cairo.Region();

        if (hides && slide_tick_id != 0) {
            region.union_rectangle(Cairo.RectangleInt() { x = 0, y = 0, width = sw, height = sh });
            gdk_surface.set_input_region(region);
            return;
        }
        if (hides && !reveal_target) {
            int hy = at_top ? sh - App.SLIVER_PX : 0;
            region.union_rectangle(Cairo.RectangleInt() { x = 0, y = hy, width = sw, height = App.SLIVER_PX });
            gdk_surface.set_input_region(region);
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
            double tx, ty;
            if (tray.translate_coordinates(this, 0, 0, out tx, out ty)) {
                int tw = tray.get_width();
                int th = tray.get_height();
                if (tw > 0 && th > 0) {
                    var trect = Cairo.RectangleInt() {
                        x = (int) tx, y = (int) ty, width = tw, height = th,
                    };
                    region.union_rectangle(trect);
                }
            }
        }

        gdk_surface.set_input_region(region);
    }
}
