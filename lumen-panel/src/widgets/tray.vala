using Gtk;

// A tray applet always contributes an icon to the compact row. Applets with a
// control surface ALSO implement IControlModule (see control_module.vala) so
// they feed the single Control Center panel; icon-only items (Clock, SysTray)
// implement just this.
public interface ITrayApplet : GLib.Object {
    public abstract Gtk.Widget tray_widget ();   // goes in the icon row
}

// The tray: an unchanged compact icon row, plus a revealer that opens the ONE
// macOS-style ControlCenter. The whole icon row is a single click target —
// clicking anywhere on it toggles the panel open at the overview. Interactive
// app-tray (SNI) buttons keep their own clicks; only passive status icons and
// empty space fall through to the toggle gesture.
public class TrayBar : Gtk.Box {

    Gtk.Box icon_row;
    // One clip-reveal widget grows the panel in BOTH dimensions off a single
    // eased animation: the Control Center is always allocated its full 600×H
    // anchored to the corner, and only the size reported upward animates, so the
    // surface blooms out of the corner with no content reflow. (Replaces the two
    // nested Gtk.Revealers, whose independent SLIDE clocks desynced and reflowed
    // the content mid-animation.)
    TrayReveal reveal;
    ControlCenter? cc = null;

    // Keeps applet instances alive (Vala connects handlers with a weak ref to
    // the handler's instance).
    Gee.ArrayList<ITrayApplet> applets = new Gee.ArrayList<ITrayApplet> ();
    Gee.ArrayList<IControlModule> modules = new Gee.ArrayList<IControlModule> ();

    public signal void expanded_changed (bool expanded);

    public TrayBar () {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class ("tray-bar");
        halign = Gtk.Align.END;
        valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END;
        if (PanelConfig.at_top) add_css_class ("at-top");
        overflow = Gtk.Overflow.HIDDEN;

        // Pin the icon row to the panel edge (bottom, or top for a top panel),
        // NOT vertically centred: the overlay stays full-height while the Control
        // Center contracts, and a centred row would float mid-box and only snap to
        // the edge once the surface shrinks. Anchored to the edge it sits in its
        // resting place throughout, so on collapse the icons simply fade back to
        // 100% in place without moving.
        icon_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END,
        };
        icon_row.add_css_class ("tray-icons");

        // Click anywhere on the row to toggle. Status icons are passive (don't
        // claim the event), so the click bubbles here; SNI app buttons claim
        // their own clicks and so don't toggle.
        var click = new Gtk.GestureClick () { button = Gdk.BUTTON_PRIMARY };
        click.released.connect (() => toggle ());
        icon_row.add_controller (click);

        reveal = new TrayReveal (PanelConfig.at_top);
        reveal.add_css_class ("tray-pages");

        // The icon row and the expanded Control Center are mutually-exclusive
        // content, but stacking them in a box made the surface jump: it dipped to
        // zero between them and snapped back to the icon-row height (the buggy
        // contraction). Overlaying them instead keeps the icon row as a permanent
        // floor, so the surface only ever animates between the compact icon-row
        // height and the full Control Center height — never to zero. The icon row
        // crossfades against the reveal fraction so the swap is seamless.
        var stack = new Gtk.Overlay ();
        stack.set_child (reveal);                     // main child: drives expanded size
        stack.add_overlay (icon_row);                 // floor: keeps the compact height
        stack.set_measure_overlay (icon_row, true);
        append (stack);

        reveal.fraction_changed.connect ((f) => {
            // Fade the icons out as the panel opens; fade them back in over the
            // last stretch of the collapse, in step with the shrinking surface.
            icon_row.opacity = (1.0 - f * 2.5).clamp (0.0, 1.0);
            // Repaint the rounded box: snapshot() interpolates its bounds by the
            // reveal fraction, so it must redraw every animation frame.
            queue_draw ();
        });
        reveal.animation_done.connect (() => {
            // Re-enable icon-row clicks only once fully collapsed. While expanded
            // the row sits (invisible) under the Control Center, so its clicks
            // must fall through to the CC controls beneath it.
            icon_row.can_target = !reveal.revealed;
        });
    }

    // Append an applet's icon and, when it's a control module, collect it for
    // the Control Center overview.
    public void add (ITrayApplet item) {
        applets.add (item);
        icon_row.append (item.tray_widget ());

        var mod = item as IControlModule;
        if (mod != null) modules.add (mod);
    }

    void ensure_cc () {
        if (cc == null) {
            cc = new ControlCenter (modules);
            reveal.child = cc;
        }
    }

    // Toggle the Control Center open/closed. Driven by a primary click on the
    // icon row AND by the panel's DBus ToggleTray method (a Wayfire keybinding),
    // so it is public. Either way the expand/collapse fires expanded_changed,
    // which the host PanelWindow uses to grow/shrink the input region.
    public void toggle () {
        if (reveal.revealed) {
            collapse ();
            return;
        }
        ensure_cc ();
        cc.show_home ();
        // The compact icons are the click-to-open affordance; once the Control
        // Center opens they're redundant. Stop them intercepting clicks meant for
        // the CC immediately; the crossfade hides them visually.
        icon_row.can_target = false;
        reveal.set_reveal (true);
        expanded_changed (true);
    }

    public void collapse () {
        if (!reveal.revealed) return;
        reveal.set_reveal (false);
        expanded_changed (false);
        if (cc != null) cc.show_home ();
    }

    public bool is_expanded ()  { return reveal.revealed; }
    public bool is_animating () { return reveal.animating; }

    // The visible rounded box. Painting it ourselves (rather than via the
    // .tray-bar CSS background) lets its bounds track the reveal fraction: the
    // widget is full-size for the whole open cycle, so a CSS background would
    // snap, but here the box grows out of / shrinks back into the compact
    // icon-row footprint anchored to the panel edge — so on collapse the box
    // itself appears to resize back to the standard compact panel.
    const float BOX_RADIUS = 18.0f;

    // The box bounds are derived from icon_row's allocation, which isn't final
    // on the first paint (it reads too narrow until something — e.g. a hover —
    // forces a repaint). Redraw whenever the layout changes so the resting box
    // always matches the current icon-row width.
    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);
        queue_draw ();
    }

    public override void snapshot (Gtk.Snapshot s) {
        int full_w = get_width ();
        int full_h = get_height ();
        if (full_w > 0 && full_h > 0) {
            // The compact footprint is icon_row's NATURAL size (padding/border
            // included) — not get_width(), which returns the content box and so
            // drops the .tray-icons horizontal padding, leaving the box too
            // narrow and clipping the first icon. measure() is also allocation-
            // independent, so it's correct on the first paint.
            int cw, ch, m, ib, nb;
            icon_row.measure (Gtk.Orientation.HORIZONTAL, -1, out m, out cw, out ib, out nb);
            icon_row.measure (Gtk.Orientation.VERTICAL,   -1, out m, out ch, out ib, out nb);
            if (cw <= 0) cw = full_w;
            if (ch <= 0) ch = full_h;

            double f = reveal.fraction;
            float bw = (float) (cw + (full_w - cw) * f);
            float bh = (float) (ch + (full_h - ch) * f);
            // Anchored to the panel edge: right always, bottom (or top for a
            // top panel) — the same corner the content blooms out of.
            float x = full_w - bw;
            float y = PanelConfig.at_top ? 0.0f : full_h - bh;

            var rect = Graphene.Rect ().init (x, y, bw, bh);
            var rr = Gsk.RoundedRect ();
            rr.init_from_rect (rect, BOX_RADIUS);
            s.push_rounded_clip (rr);
            s.append_color (Theme.color ("tray.background", "rgba(17,20,31,0.97)"), rect);
            s.pop ();
        }
        base.snapshot (s);
    }
}
