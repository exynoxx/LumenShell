// Applets with a control surface also implement IControlModule; icon-only items
// (Clock, SysTray) implement just this.
public interface ITrayApplet : GLib.Object {
    public abstract Gtk.Widget tray_widget ();   // goes in the icon row
}

public class TrayBar : Gtk.Box {

    Gtk.Box icon_row;
    TrayReveal reveal;
    ControlCenter? cc = null;

    // Keeps applet instances alive (Vala connects handlers with a weak ref to
    // the handler's instance).
    Gee.ArrayList<ITrayApplet> applets = new Gee.ArrayList<ITrayApplet> ();
    Gee.ArrayList<IControlModule> modules = new Gee.ArrayList<IControlModule> ();

    public signal void expanded_changed ();

    LogindBridge logind;
    BrightnessService brightness;

    public TrayBar (LogindBridge logind, BrightnessService brightness) {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.logind = logind;
        this.brightness = brightness;
        add_css_class ("tray-bar");
        halign = Gtk.Align.END;
        valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END;
        if (PanelConfig.at_top) add_css_class ("at-top");
        overflow = Gtk.Overflow.HIDDEN;

        // Pinned to the panel edge, not centred: the overlay stays full-height while
        // the CC contracts, so a centred row would float mid-box during collapse.
        icon_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            valign = PanelConfig.at_top ? Gtk.Align.START : Gtk.Align.END,
        };
        icon_row.add_css_class ("tray-icons");

        // Status icons don't claim the click, so it bubbles here; SNI buttons claim theirs.
        var click = new Gtk.GestureClick () { button = Gdk.BUTTON_PRIMARY };
        click.released.connect (() => toggle ());
        icon_row.add_controller (click);

        var motion = new Gtk.EventControllerMotion ();
        motion.motion.connect ((x, y) => {
            bool over_sni = false;
            for (var w = icon_row.pick (x, y, Gtk.PickFlags.DEFAULT); w != null && w != icon_row; w = w.get_parent ())
                if (w.has_css_class ("systray")) { over_sni = true; break; }
            if (over_sni) icon_row.remove_css_class ("row-hover");
            else icon_row.add_css_class ("row-hover");
        });
        motion.leave.connect (() => icon_row.remove_css_class ("row-hover"));
        icon_row.add_controller (motion);

        reveal = new TrayReveal (PanelConfig.at_top);
        reveal.add_css_class ("tray-pages");

        // Overlay, not a Box: the icon row is a permanent floor so the surface never
        // dips to zero height between the compact row and the Control Center.
        var stack = new Gtk.Overlay ();
        stack.set_child (reveal);                     // main child: drives expanded size
        stack.add_overlay (icon_row);                 // floor: keeps the compact height
        stack.set_measure_overlay (icon_row, true);
        append (stack);

        reveal.fraction_changed.connect ((f) => {
            icon_row.opacity = (1.0 - f * 2.5).clamp (0.0, 1.0);
            // snapshot() interpolates the box bounds by the fraction: redraw every frame.
            queue_draw ();
        });
        reveal.animation_done.connect (() => {
            // While expanded the invisible row sits over the CC; its clicks must fall through.
            icon_row.can_target = !reveal.revealed;
        });
    }

    public void add (ITrayApplet item) {
        applets.add (item);
        icon_row.append (item.tray_widget ());

        var mod = item as IControlModule;
        if (mod != null) modules.add (mod);
    }

    void ensure_cc () {
        if (cc == null) {
            cc = new ControlCenter (modules, logind, brightness);
            reveal.child = cc;
        }
    }

    // Public: also driven by the panel's DBus ToggleTray (Wayfire keybinding).
    public void toggle () {
        if (reveal.revealed) {
            collapse ();
            return;
        }
        ensure_cc ();
        cc.show_home ();
        icon_row.can_target = false;
        reveal.set_reveal (true);
        expanded_changed ();
    }

    public void collapse () {
        if (!reveal.revealed) return;
        reveal.set_reveal (false);
        expanded_changed ();
        if (cc != null) cc.show_home ();
    }

    public bool is_expanded ()  { return reveal.revealed; }
    public bool is_animating () { return reveal.animating; }

    // Painted here rather than via CSS so the box bounds can track the reveal
    // fraction (the widget itself is full-size for the whole open cycle).
    const float BOX_RADIUS = 18.0f;

    // icon_row's allocation isn't final on the first paint; redraw on every
    // layout change so the resting box matches its width.
    public override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);
        queue_draw ();
    }

    public override void snapshot (Gtk.Snapshot s) {
        int full_w = get_width ();
        int full_h = get_height ();
        if (full_w > 0 && full_h > 0) {
            // icon_row's NATURAL size, not get_width(): the latter drops the .tray-icons
            // padding and clips the first icon, and measure() is valid on the first paint.
            int cw, ch, m, ib, nb;
            icon_row.measure (Gtk.Orientation.HORIZONTAL, -1, out m, out cw, out ib, out nb);
            icon_row.measure (Gtk.Orientation.VERTICAL,   -1, out m, out ch, out ib, out nb);
            if (cw <= 0) cw = full_w;
            if (ch <= 0) ch = full_h;

            double f = reveal.fraction;
            float bw = (float) (cw + (full_w - cw) * f);
            float bh = (float) (ch + (full_h - ch) * f);
            float x = full_w - bw;
            float y = PanelConfig.at_top ? 0.0f : full_h - bh;

            Utils.fill_rounded (s, x, y, bw, bh, BOX_RADIUS,
                                Theme.color ("tray.background", "rgba(17,20,31,0.97)"));
        }
        base.snapshot (s);
    }
}
