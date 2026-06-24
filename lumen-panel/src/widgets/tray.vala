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
    // Two nested revealers so the panel grows in BOTH dimensions at once: the
    // outer one animates width (right edge pinned → it blooms leftward), the
    // inner one animates height (icon row pinned to the bottom-anchored box →
    // the icons slide up). The Control Center is always allocated its full
    // 600×H, so the revealers only clip a growing rectangle out of a corner —
    // no content reflow mid-animation. Collapsing retracts both back to the
    // compact icon-row size.
    Gtk.Revealer width_rev;
    Gtk.Revealer height_rev;
    public Gtk.Revealer revealer { get { return width_rev; } }
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

        icon_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.CENTER,
        };
        icon_row.add_css_class ("tray-icons");
        append (icon_row);

        // Click anywhere on the row to toggle. Status icons are passive (don't
        // claim the event), so the click bubbles here; SNI app buttons claim
        // their own clicks and so don't toggle.
        var click = new Gtk.GestureClick () { button = Gdk.BUTTON_PRIMARY };
        click.released.connect (() => toggle ());
        icon_row.add_controller (click);

        height_rev = new Gtk.Revealer () {
            transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
            transition_duration = 300,
            reveal_child = false,
        };
        width_rev = new Gtk.Revealer () {
            transition_type = Gtk.RevealerTransitionType.SLIDE_LEFT,
            transition_duration = 300,
            reveal_child = false,
            halign = Gtk.Align.END,
            child = height_rev,
        };
        width_rev.add_css_class ("tray-pages");
        append (width_rev);
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
            height_rev.child = cc;
        }
    }

    void toggle () {
        if (width_rev.reveal_child) {
            collapse ();
            return;
        }
        ensure_cc ();
        cc.show_home ();
        // The compact status icons are the click-to-open affordance; once the
        // Control Center is open they're redundant, so hide them and let the
        // panel be the single expanded surface.
        icon_row.visible = false;
        width_rev.reveal_child = true;
        height_rev.reveal_child = true;
        expanded_changed (true);
    }

    public void collapse () {
        if (!width_rev.reveal_child) return;
        width_rev.reveal_child = false;
        height_rev.reveal_child = false;
        icon_row.visible = true;
        expanded_changed (false);
        if (cc != null) cc.show_home ();
    }

    public bool is_expanded () { return width_rev.reveal_child; }
}
