public interface IControlModule : GLib.Object {
    public abstract string      module_id ();   // "wifi", "bluetooth", …
    public abstract Gtk.Widget  home_tile ();   // shown in the overview
    public abstract Gtk.Widget? detail_view (); // inline detail, or null

    public signal void open_detail ();
}

// Colours for code-drawn widgets (mirrors .cc-* in style.css). MUST stay `const`:
// nothing instantiates CcStyle, so class_init never runs and a static initialized
// from a function call would read back transparent.
public class CcStyle {
    public const Gdk.RGBA accent       = { 0.039f, 0.518f, 1.0f,   1f };    // #0A84FF
    public const Gdk.RGBA green        = { 0.204f, 0.780f, 0.349f, 1f };    // #34C759
    public const Gdk.RGBA label        = { 1f, 1f, 1f, 1f };
    public const Gdk.RGBA separator    = { 1f, 1f, 1f, 0.10f };
    public const Gdk.RGBA row_selected = { 0.039f, 0.518f, 1.0f, 0.18f };
    public const Gdk.RGBA row_hover    = { 1f, 1f, 1f, 0.06f };

    public static string icon (string name) {
        return "/dev/lumen/panel/icons/" + name + ".svg";
    }
}

// `key` survives a rescan (SSID, MAC) so selection is restored after a rebuild.
public interface CcRow : Gtk.Widget {
    public abstract string key      { get; }
    public abstract bool   selected { get; set; }
}

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
        var chev = new Gtk.Label ("‹");
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

// Selection is tracked by row key so it survives the rebuild a background scan
// triggers. Subclasses supply only the rows.
public abstract class CcListDetail : CcDetail {

    protected Gtk.Switch  power_switch;
    protected Gtk.Button  refresh_btn;
    protected Gtk.Spinner spinner;

    // The body column; subclasses append their cards into it in display order.
    protected Gtk.Box            content;
    protected Gtk.ScrolledWindow list_scroll;
    protected Gtk.Label          empty_label;

    protected Gee.ArrayList<CcRow> rows = new Gee.ArrayList<CcRow> ();
    protected string selected_key = "";

    // Guards the switch's notify handler while we mirror the service state onto
    // it, so syncing doesn't read back as a user toggle.
    bool syncing_power = false;

    protected abstract void power_requested (bool on);
    protected abstract void refresh_requested ();

    protected CcListDetail (string title, string css_class) {
        base ();
        add_css_class (css_class);

        var trailing = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            valign = Gtk.Align.CENTER,
        };

        spinner = new Gtk.Spinner () { valign = Gtk.Align.CENTER, visible = false };
        trailing.append (spinner);

        refresh_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        refresh_btn.add_css_class ("cc-icon-btn");
        refresh_btn.set_child (new Gtk.Label ("⟲"));
        refresh_btn.clicked.connect (() => refresh_requested ());
        trailing.append (refresh_btn);

        power_switch = new Gtk.Switch () { valign = Gtk.Align.CENTER };
        power_switch.add_css_class ("lumen-switch");
        power_switch.notify["active"].connect (() => {
            if (syncing_power) return;
            power_requested (power_switch.active);
        });
        trailing.append (power_switch);

        append (make_header (title, trailing));

        content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
            margin_start = 14, margin_end = 14, margin_bottom = 14, vexpand = true,
        };
        append (content);

        empty_label = new Gtk.Label ("") {
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
            vexpand = true, can_target = false, visible = false,
        };
        empty_label.add_css_class ("cc-empty");
    }

    protected Gtk.ScrolledWindow make_list_scroll (Gtk.Widget child) {
        list_scroll = new Gtk.ScrolledWindow () {
            child = child,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
            vexpand = true,
            min_content_height = 240,
            max_content_height = 380,
            propagate_natural_height = true,
        };
        list_scroll.add_css_class ("cc-scroll");
        return list_scroll;
    }

    protected void sync_header (bool powered, bool scanning) {
        if (power_switch.active != powered) {
            syncing_power = true;
            power_switch.active = powered;
            syncing_power = false;
        }
        refresh_btn.sensitive = powered;
        refresh_btn.visible   = !scanning;
        spinner.visible       = scanning;
        spinner.spinning      = scanning;
    }

    protected void set_empty (string msg) {
        empty_label.label   = msg;
        empty_label.visible = msg != "";
    }

    protected void select_key (string key) {
        selected_key = key;
        foreach (var r in rows) r.selected = (r.key == key);
    }

    protected void clear_selection () {
        select_key ("");
    }

    protected bool has_key (string key) {
        foreach (var r in rows) if (r.key == key) return true;
        return false;
    }
}

// Toggle and nav area are separate buttons: the circle flips the radio, the
// label opens the detail.
public class CcToggleRow : Gtk.Box {

    public signal void toggled (bool want_on);
    public signal void activated ();

    Gtk.Button toggle_btn;
    Gtk.Image  toggle_img;
    Gtk.Label  subtitle_lbl;
    string on_icon;
    string off_icon;
    bool _on = false;

    // compact: half-width tile — no chevron, ellipsized subtitle.
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
            // Ellipsize against the real allocation; a max-width-chars cap clips ordinary SSIDs.
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
            var chev = new Gtk.Label ("›") { valign = Gtk.Align.CENTER };
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
