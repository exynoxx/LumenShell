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
    public Gtk.Revealer revealer { get; private set; }
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

        revealer = new Gtk.Revealer () {
            transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
            transition_duration = 280,
            reveal_child = false,
        };
        revealer.add_css_class ("tray-pages");
        append (revealer);
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
            revealer.child = cc;
        }
    }

    void toggle () {
        if (revealer.reveal_child) {
            collapse ();
            return;
        }
        ensure_cc ();
        cc.show_home ();
        revealer.reveal_child = true;
        expanded_changed (true);
    }

    public void collapse () {
        if (!revealer.reveal_child) return;
        revealer.reveal_child = false;
        expanded_changed (false);
        if (cc != null) cc.show_home ();
    }

    public bool is_expanded () { return revealer.reveal_child; }
}
