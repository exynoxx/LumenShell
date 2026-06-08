using Gtk;

public class App : GLib.Object {

    public const int ICON_ROW_HEIGHT = 60;
    // Grace period before the tray collapses after the pointer leaves the
    // bounded area. Lenient enough to forgive diagonal mouse paths that clip
    // the concave corner between the bottom strip and the expanded tray.
    public const uint COLLAPSE_DELAY_MS = 500;

    // Auto-hide: when enabled the panel slides off the bottom edge, leaving a
    // SLIVER_PX handle on-screen as the reveal hot-zone. Hidden state shifts the
    // surface down by HIDDEN_MARGIN via a negative layer-shell bottom margin.
    public const int SLIVER_PX = 4;
    public const int HIDDEN_MARGIN = -(ICON_ROW_HEIGHT - SLIVER_PX);
    public const int64 REVEAL_ANIM_US = 200000; // 200ms

    Gtk.ApplicationWindow win;
    TrayBar tray;
    uint collapse_timeout_id = 0;
    uint resize_tick_id = 0;

    bool auto_hide = false;
    bool reveal_target = false;     // where the slide is heading
    int current_margin = 0;         // last applied bottom margin
    int slide_from_margin = 0;      // margin at animation start
    int64 slide_start_us = 0;       // frame time at animation start
    uint slide_tick_id = 0;

    public void activate (Gtk.Application app) {
        win = new Gtk.ApplicationWindow(app);
        win.add_css_class("lumen-panel");
        win.set_default_size(-1, 60);

        var panel_ini = Environment.get_user_config_dir() + "/lumen-shell/panel.ini";
        auto_hide = Ini.get_key_value(panel_ini, "behavior.auto-hide") == "true";

        GtkLayerShell.init_for_window(win);
        GtkLayerShell.set_namespace(win, "lumen-panel");
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.TOP);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT,   true);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT,  true);
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, true);
        GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.ON_DEMAND);

        if (auto_hide) {
            // Don't reserve screen space; start hidden with only the handle showing.
            GtkLayerShell.set_exclusive_zone(win, 0);
            current_margin = HIDDEN_MARGIN;
            GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, HIDDEN_MARGIN);
            // In auto-hide mode fill the panel backdrop with a translucent
            // color (icons stay fully opaque on top) so it reads as a bar over
            // the windows it now floats above.
            win.add_css_class("auto-hide");
        } else {
            GtkLayerShell.set_exclusive_zone(win, 60);
        }

        Theme.install();

        // Bind foreign-toplevel before building the AppBar so replay happens
        // synchronously when AppBar subscribes inside its constructor.
        ToplevelStore.instance.bind();

        // Root: AppBar on the left, TrayBar on the right.
        var root = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
            hexpand = true, vexpand = true,
            valign = Gtk.Align.END,
        };

        var app_bar = new AppBar();
        root.append(app_bar);

        tray = new TrayBar();
        tray.add_paged(new WifiTray());
        tray.add_paged(new BluetoothTray());
        tray.add_paged(new BatteryTray());
        tray.add_paged(new SoundTray());
        tray.add_icon(new Clock());
        tray.add_paged(new ExitTray());
        root.append(tray);

#if PANEL_PEEK
        // Clicking the empty middle of the panel (not an app icon, not the
        // tray) triggers the same Wayfire desktop-peek as Win+D and as
        // clicking blank space on the lumen desktop. App icons and tray
        // buttons are Gtk.Buttons; the tray box is skipped by reference. We
        // walk up from the picked widget so a child gesture that doesn't
        // claim the press can't sneak a peek in behind a real click.
        var peek_click = new Gtk.GestureClick();
        peek_click.set_button(Gdk.BUTTON_PRIMARY);
        peek_click.pressed.connect((n_press, x, y) => {
            var picked = root.pick(x, y, Gtk.PickFlags.DEFAULT);
            for (var w = picked; w != null && w != root; w = w.get_parent()) {
                if (w is Gtk.Button || w is Gtk.Editable || w == tray)
                    return;
            }
            PeekIpc.toggle();
        });
        root.add_controller(peek_click);
#endif

        // The panel backdrop is a fixed-height strip pinned to the bottom edge,
        // not the window background. The layer-shell surface grows upward when
        // the tray expands a page; painting the color on the window would drag
        // the backdrop up with it. A spacer pushes the colored strip to the
        // bottom so it stays ICON_ROW_HEIGHT tall regardless of surface height.
        var backdrop = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
            hexpand = true, vexpand = true,
        };
        backdrop.append(new Gtk.Box(Gtk.Orientation.VERTICAL, 0) { vexpand = true });
        var strip = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
            hexpand = true, height_request = ICON_ROW_HEIGHT,
        };
        strip.add_css_class("panel-strip");
        backdrop.append(strip);

        // Overlay: backdrop behind (bottom z-order), content on top. The content
        // layer is measured so the surface still grows with the tray's pages.
        var overlay = new Gtk.Overlay();
        overlay.set_child(backdrop);
        overlay.add_overlay(root);
        overlay.set_measure_overlay(root, true);

        win.set_child(overlay);
        win.present();

        // ESC anywhere on the panel collapses the tray. CAPTURE phase so
        // the window sees the key before any focused child can swallow it
        // (e.g. the WiFi password field).
        var esc = new Gtk.EventControllerKey();
        esc.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        esc.key_pressed.connect((keyval, keycode, mods) => {
            if (keyval == Gdk.Key.Escape && tray.is_expanded()) {
                tray.collapse();
                return true;
            }
            return false;
        });
        ((Gtk.Widget) win).add_controller(esc);

        // Input region: re-apply when the surface is mapped or the tray
        // reveals/hides its page area. The revealer notify hooks fire only
        // at the start and end of the animation; the layer-shell surface
        // grows incrementally between those two points. While the
        // transition is in progress, a tick callback re-applies the input
        // region every frame so it stays aligned with the new buffer size.
        // Without this, the input region remains in old surface
        // coordinates during the resize and the compositor fires a
        // wl_pointer.leave when the cursor's new surface-local position
        // lands outside the stale region — with a stationary mouse no
        // matching enter follows, so the hover-out timer collapses the
        // tray right after click.
        win.map.connect(update_input_region);
        tray.revealer.notify["reveal-child"].connect(() => {
            update_input_region();
            start_resize_tracking();
        });
        tray.revealer.notify["child-revealed"].connect(update_input_region);

        // Hover-out collapse. contains-pointer on a window-level motion
        // controller is the right signal source provided the input region
        // tracks the surface size (see above).
        var win_motion = new Gtk.EventControllerMotion();
        win_motion.notify["contains-pointer"].connect(() => {
            if (win_motion.contains_pointer) {
                cancel_collapse();
                if (auto_hide) set_reveal(true);
                return;
            }
            if (tray.is_expanded() || auto_hide) schedule_collapse();
        });
        ((Gtk.Widget) win).add_controller(win_motion);
    }

    // Drive the slide toward revealed (margin 0) or hidden (HIDDEN_MARGIN).
    void set_reveal (bool reveal) {
        if (!auto_hide) return;
        if (reveal == reveal_target && slide_tick_id == 0) {
            // Already settled in the requested state; nothing to animate.
            int settled = reveal ? 0 : HIDDEN_MARGIN;
            if (current_margin == settled) return;
        }
        reveal_target = reveal;
        start_slide_tracking();
    }

    void start_slide_tracking () {
        slide_from_margin = current_margin;
        slide_start_us = 0; // stamped on first tick from the frame clock
        if (slide_tick_id != 0) return;
        slide_tick_id = ((Gtk.Widget) win).add_tick_callback((widget, clock) => {
            int target = reveal_target ? 0 : HIDDEN_MARGIN;
            if (slide_start_us == 0) slide_start_us = clock.get_frame_time();
            double t = (double) (clock.get_frame_time() - slide_start_us) / REVEAL_ANIM_US;
            if (t >= 1.0) {
                current_margin = target;
                GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, current_margin);
                update_input_region();
                slide_tick_id = 0;
                return GLib.Source.REMOVE;
            }
            // ease-out for a softer settle
            double eased = 1.0 - (1.0 - t) * (1.0 - t);
            current_margin = (int) (slide_from_margin + (target - slide_from_margin) * eased);
            GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, current_margin);
            update_input_region();
            return GLib.Source.CONTINUE;
        });
    }

    void start_resize_tracking () {
        if (resize_tick_id != 0) return;
        resize_tick_id = ((Gtk.Widget) win).add_tick_callback((widget, clock) => {
            update_input_region();
            if (tray.revealer.reveal_child == tray.revealer.child_revealed) {
                resize_tick_id = 0;
                return GLib.Source.REMOVE;
            }
            return GLib.Source.CONTINUE;
        });
    }

    void schedule_collapse () {
        if (collapse_timeout_id != 0) return;
        collapse_timeout_id = GLib.Timeout.add(COLLAPSE_DELAY_MS, () => {
            collapse_timeout_id = 0;
            if (tray.is_expanded()) tray.collapse();
            // Don't slide away mid-interaction with an open tray page.
            if (auto_hide && !tray.is_expanded()) set_reveal(false);
            return GLib.Source.REMOVE;
        });
    }

    void cancel_collapse () {
        if (collapse_timeout_id == 0) return;
        GLib.Source.remove(collapse_timeout_id);
        collapse_timeout_id = 0;
    }

    // Clip the layer-shell surface's input region to the parts the user can
    // actually click: the bottom 60px strip (AppBar + TrayBar icon row when
    // collapsed) plus the tray's full bounding box when expanded. The latter
    // is necessary because expanding pushes the tray's icon row UP, above
    // the bottom strip — without it, other tray icons become unclickable
    // while a page is open. GtkPopovers are separate xdg_popups and don't
    // go through this region.
    void update_input_region () {
        var gdk_surface = win.get_surface();
        if (gdk_surface == null) return;

        int sw = win.get_width();
        int sh = win.get_height();
        if (sw <= 0 || sh <= 0) return;

        var region = new Cairo.Region();

        // Auto-hide: while sliding, claim the whole surface so a spurious
        // pointer-leave can't abort an in-flight reveal. When settled hidden,
        // claim only the on-screen handle strip (top SLIVER_PX) as the hot-zone.
        if (auto_hide && slide_tick_id != 0) {
            region.union_rectangle(Cairo.RectangleInt() { x = 0, y = 0, width = sw, height = sh });
            gdk_surface.set_input_region(region);
            return;
        }
        if (auto_hide && !reveal_target) {
            region.union_rectangle(Cairo.RectangleInt() { x = 0, y = 0, width = sw, height = SLIVER_PX });
            gdk_surface.set_input_region(region);
            return;
        }

        var bottom = Cairo.RectangleInt() {
            x = 0,
            y = sh - ICON_ROW_HEIGHT,
            width = sw,
            height = ICON_ROW_HEIGHT,
        };
        region.union_rectangle(bottom);

        if (tray.revealer.reveal_child || tray.revealer.child_revealed) {
            double tx, ty;
            if (tray.translate_coordinates(win, 0, 0, out tx, out ty)) {
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

int main (string[] args) {
    var app = new Gtk.Application("dev.lumen.panel", GLib.ApplicationFlags.DEFAULT_FLAGS);
    var holder = new App();
    app.activate.connect(() => holder.activate(app));
    return app.run(args);
}
