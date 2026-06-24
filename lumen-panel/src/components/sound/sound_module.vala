using Gtk;

// Overview tile for Sound: a mute toggle (the speaker glyph) + a thick macOS
// slider. No detail view — volume lives entirely inline.
public class SoundModule : GLib.Object {

    SoundService service;
    Gtk.Box   row;
    Gtk.Image mute_img;
    CcSlider  slider;
    bool      suppress = false;

    public SoundModule (SoundService service) {
        this.service = service;

        row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
            margin_start = 12, margin_end = 14, margin_top = 8, margin_bottom = 8,
        };

        var mute_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };
        mute_btn.add_css_class ("cc-icon-btn");
        mute_img = new Gtk.Image () { pixel_size = 20 };
        mute_img.set_from_resource (CcStyle.icon ("sound-max"));
        mute_btn.set_child (mute_img);
        mute_btn.clicked.connect (() => service.toggle_mute ());
        row.append (mute_btn);

        slider = new CcSlider () { valign = Gtk.Align.CENTER, hexpand = true };
        slider.value_changed.connect ((pct) => {
            if (suppress) return;
            service.change_volume (pct);
        });
        row.append (slider);

        service.state_changed.connect (refresh);
        refresh ();
    }

    public Gtk.Widget tile () { return row; }

    void refresh () {
        suppress = true;
        slider.set_value (service.volume_percent);
        suppress = false;
        mute_img.set_from_resource (CcStyle.icon (service.muted ? "sound-mute" : "sound-max"));
    }
}
