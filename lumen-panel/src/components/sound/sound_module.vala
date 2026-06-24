using Gtk;

// Overview tile for Sound: a mute toggle (the speaker glyph) + a thick macOS
// slider, plus an "Output" nav row showing the active device that slides the
// Control Center to the device picker (SoundDetail).
public class SoundModule : GLib.Object {

    public signal void open_requested ();

    SoundService service;
    Gtk.Box   root;
    Gtk.Image mute_img;
    CcSlider  slider;
    Gtk.Label device_lbl;
    bool      suppress = false;

    public SoundModule (SoundService service) {
        this.service = service;

        root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

        var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
            margin_start = 12, margin_end = 14, margin_top = 8, margin_bottom = 8,
        };

        var mute_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        mute_btn.add_css_class ("cc-icon-btn");
        mute_img = new Gtk.Image () { pixel_size = 20 };
        mute_img.set_from_resource (CcStyle.icon ("sound-max"));
        mute_btn.set_child (mute_img);
        mute_btn.clicked.connect (() => service.toggle_mute ());
        top.append (mute_btn);

        slider = new CcSlider () { valign = Gtk.Align.CENTER, hexpand = true };
        slider.value_changed.connect ((pct) => {
            if (suppress) return;
            service.change_volume (pct);
        });
        top.append (slider);
        root.append (top);

        var sep = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            height_request = 1, margin_start = 12,
        };
        sep.add_css_class ("cc-row-sep");
        root.append (sep);

        // "Output  ›  Device" nav row — opens the device picker.
        var navbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { valign = Gtk.Align.CENTER };
        var out_lbl = new Gtk.Label ("Output") { xalign = 0 };
        out_lbl.add_css_class ("cc-row-title");
        navbox.append (out_lbl);
        navbox.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });
        device_lbl = new Gtk.Label ("") {
            xalign = 1, valign = Gtk.Align.CENTER,
            ellipsize = Pango.EllipsizeMode.END, max_width_chars = 18,
        };
        device_lbl.add_css_class ("cc-row-subtitle");
        navbox.append (device_lbl);
        var chev = new Gtk.Label ("›") { valign = Gtk.Align.CENTER };
        chev.add_css_class ("cc-chevron");
        navbox.append (chev);

        var nav = new Gtk.Button () { hexpand = true };
        nav.add_css_class ("cc-nav");
        nav.set_child (navbox);
        nav.clicked.connect (() => open_requested ());
        root.append (nav);

        service.state_changed.connect (refresh);
        refresh ();
    }

    public Gtk.Widget tile () { return root; }

    void refresh () {
        suppress = true;
        slider.set_value (service.volume_percent);
        suppress = false;
        mute_img.set_from_resource (CcStyle.icon (service.muted ? "sound-mute" : "sound-max"));
        device_lbl.label = active_sink_name ();
    }

    string active_sink_name () {
        foreach (var s in service.sinks)
            if (s.id == service.default_sink) return s.name;
        return service.sinks.length > 0 ? service.sinks[0].name : "";
    }
}
