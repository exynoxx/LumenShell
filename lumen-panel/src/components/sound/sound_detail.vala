using Gtk;

// Inline Sound detail the Control Center slides to: the list of output devices
// (PulseAudio/PipeWire sinks) as selectable rows, the active one marked with a
// blue check. Tapping a row makes it the default sink. Rebuilt on every service
// poll so hotplugged devices appear/disappear live.
public class SoundDetail : CcDetail {

    SoundService service;
    Gtk.Box list_card;
    Gtk.Label empty_label;

    public SoundDetail (SoundService service) {
        base ();
        this.service = service;
        add_css_class ("wifi-detail");

        append (make_header ("Output", null));

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
            margin_start = 14, margin_end = 14, margin_bottom = 14, vexpand = true,
        };

        list_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { hexpand = true };
        list_card.add_css_class ("cc-card");
        content.append (list_card);

        empty_label = new Gtk.Label ("No output devices") {
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER,
            vexpand = true, can_target = false, visible = false,
        };
        empty_label.add_css_class ("cc-empty");
        content.append (empty_label);

        append (content);

        service.state_changed.connect (rebuild);
        rebuild ();
    }

    void rebuild () {
        Gtk.Widget? w;
        while ((w = list_card.get_first_child ()) != null) list_card.remove (w);

        var sinks = service.sinks;
        empty_label.visible = sinks.length == 0;
        list_card.visible   = sinks.length > 0;

        for (int i = 0; i < sinks.length; i++) {
            var sink = sinks[i];
            if (i > 0) {
                var sep = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                    height_request = 1, margin_start = 14,
                };
                sep.add_css_class ("cc-row-sep");
                list_card.append (sep);
            }

            var rowbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { valign = Gtk.Align.CENTER };
            var name = new Gtk.Label (sink.name) {
                xalign = 0, hexpand = true, valign = Gtk.Align.CENTER,
                ellipsize = Pango.EllipsizeMode.END,
            };
            name.add_css_class ("cc-row-title");
            rowbox.append (name);

            if (sink.id == service.default_sink) {
                var check = new Gtk.Label ("✓") { valign = Gtk.Align.CENTER };
                check.add_css_class ("cc-check");
                rowbox.append (check);
            }

            var btn = new Gtk.Button () { hexpand = true };
            btn.add_css_class ("cc-nav");
            btn.set_child (rowbox);
            string id = sink.id;
            btn.clicked.connect (() => service.change_default_sink (id));
            list_card.append (btn);
        }
    }
}
