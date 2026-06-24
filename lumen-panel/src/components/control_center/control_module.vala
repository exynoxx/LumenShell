using Gtk;

// macOS-Control-Center model. The compact icon row is unchanged; expanding the
// tray reveals ONE ControlCenter panel of round toggles + info tiles. A tray
// applet that has a control surface implements IControlModule in addition to
// ITrayApplet: it contributes a home tile to the overview and, optionally, an
// inline detail view (the WiFi/Bluetooth network lists) the panel slides to.
public interface IControlModule : GLib.Object {
    public abstract string      module_id ();   // "wifi", "bluetooth", …
    public abstract Gtk.Widget  home_tile ();   // shown in the overview
    public abstract Gtk.Widget? detail_view (); // inline detail, or null

    // Emitted when the module's home tile is activated and wants the Control
    // Center to slide to its detail view. ControlCenter wires every module's
    // signal to open(module_id) — the module just fires it.
    public signal void open_detail ();
}

// Shared Apple-dark tokens for the code-drawn widgets (CSS @define-color can't
// reach Gsk/Cairo draw paths). Mirrors the .cc-* values in style.css.
public class CcStyle {
    public static Gdk.RGBA accent      = Utils.rgba(0.039f, 0.518f, 1.0f,  1f);   // #0A84FF
    public static Gdk.RGBA green       = Utils.rgba(0.204f, 0.780f, 0.349f, 1f);  // #34C759
    public static Gdk.RGBA label       = Utils.rgba(1f, 1f, 1f, 1f);
    public static Gdk.RGBA label2      = Utils.rgba(0.921f, 0.921f, 0.960f, 0.60f);
    public static Gdk.RGBA label3      = Utils.rgba(0.921f, 0.921f, 0.960f, 0.30f);
    public static Gdk.RGBA separator   = Utils.rgba(1f, 1f, 1f, 0.10f);
    public static Gdk.RGBA fill_hover  = Utils.rgba(1f, 1f, 1f, 0.08f);
    public static Gdk.RGBA danger      = Utils.rgba(1.0f, 0.271f, 0.227f, 1f);    // #FF453A

    public static string icon (string name) {
        return "/dev/lumen/panel/icons/" + name + ".svg";
    }
}

// A detail view the ControlCenter slides to. Carries a back affordance so the
// panel can return to the overview; the concrete WiFi/Bluetooth details extend
// this and call make_header() for the consistent "‹  Title  [trailing]" chrome.
public abstract class CcDetail : Gtk.Box {
    public signal void back_requested ();

    protected CcDetail () {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        add_css_class ("cc-detail");
    }

    protected Gtk.Widget make_header (string title, Gtk.Widget? trailing) {
        var h = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            margin_start = 6, margin_end = 14, margin_top = 12, margin_bottom = 10,
        };

        var back = new Gtk.Button () { valign = Gtk.Align.CENTER };
        back.add_css_class ("cc-back");
        var chev = new Gtk.Label ("‹");           // ‹
        chev.add_css_class ("cc-back-chevron");
        back.set_child (chev);
        back.clicked.connect (() => back_requested ());
        h.append (back);

        var title_lbl = new Gtk.Label (title) {
            xalign = 0, valign = Gtk.Align.CENTER, hexpand = true,
        };
        title_lbl.add_css_class ("cc-detail-title");
        h.append (title_lbl);

        if (trailing != null) {
            trailing.valign = Gtk.Align.CENTER;
            h.append (trailing);
        }
        return h;
    }
}

// macOS connectivity row: a round toggle (the circular icon) plus a flat
// activation area (title + live subtitle + chevron). The toggle and the nav
// area are distinct buttons so tapping the circle flips the radio while tapping
// the label opens the detail — exactly like Control Center.
public class CcToggleRow : Gtk.Box {

    public signal void toggled (bool want_on);
    public signal void activated ();

    Gtk.Button toggle_btn;
    Gtk.Image  toggle_img;
    Gtk.Label  subtitle_lbl;
    string on_icon;
    string off_icon;
    bool _on = false;

    // compact: half-width tile that sits beside a sibling (Wi-Fi next to
    // Bluetooth) — drops the chevron and ellipsizes the live subtitle so a long
    // network name can't blow out the tile width.
    public CcToggleRow (string title, string on_icon, string off_icon, bool compact = false) {
        GLib.Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
        add_css_class ("cc-row");
        this.on_icon = on_icon;
        this.off_icon = off_icon;

        toggle_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        toggle_btn.add_css_class ("cc-toggle");
        toggle_img = new Gtk.Image () { pixel_size = 20 };
        toggle_img.set_from_resource (CcStyle.icon (off_icon));
        toggle_btn.set_child (toggle_img);
        toggle_btn.clicked.connect (() => toggled (!_on));
        append (toggle_btn);

        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 1) {
            valign = Gtk.Align.CENTER,
        };
        var title_lbl = new Gtk.Label (title) { xalign = 0 };
        title_lbl.add_css_class ("cc-row-title");
        subtitle_lbl = new Gtk.Label ("") { xalign = 0 };
        subtitle_lbl.add_css_class ("cc-row-subtitle");
        if (compact) {
            // Let the live subtitle (network name) take the whole tile width and
            // ellipsize only against the actual allocation — a fixed
            // max-width-chars cap clipped ordinary SSIDs ("WiFimodem-4903-5").
            subtitle_lbl.ellipsize = Pango.EllipsizeMode.END;
            text.hexpand = true;
        }
        text.append (title_lbl);
        text.append (subtitle_lbl);

        var navbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        navbox.append (text);
        if (!compact) {
            var grow = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true };
            navbox.append (grow);
            var chev = new Gtk.Label ("›") { valign = Gtk.Align.CENTER };  // ›
            chev.add_css_class ("cc-chevron");
            navbox.append (chev);
        }

        var nav = new Gtk.Button () { hexpand = true };
        nav.add_css_class ("cc-nav");
        nav.set_child (navbox);
        nav.clicked.connect (() => activated ());
        append (nav);
    }

    public void set_on (bool on) {
        _on = on;
        if (on) toggle_btn.add_css_class ("on");
        else    toggle_btn.remove_css_class ("on");
        toggle_img.set_from_resource (CcStyle.icon (on ? on_icon : off_icon));
    }

    public void set_subtitle (string s) {
        subtitle_lbl.label = s;
    }
}
