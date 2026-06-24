using Gtk;

// Overview tile for Battery: an icon, the percentage, a status subtitle, and
// the power-profile segmented control (only when a backend exists). No detail
// view — the full stats page is gone in the Control Center model.
public class BatteryModule : GLib.Object {

    BatteryService service;
    PowerProfileService pps;

    Gtk.Box   root;
    Gtk.Image icon_img;
    Gtk.Label status_lbl;
    Gtk.Label pct_lbl;
    SegmentedControl seg;

    public BatteryModule (BatteryService service, PowerProfileService pps) {
        this.service = service;
        this.pps = pps;

        root = new Gtk.Box (Gtk.Orientation.VERTICAL, 10) {
            margin_start = 14, margin_end = 14, margin_top = 10, margin_bottom = 12,
        };

        var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        icon_img = new Gtk.Image () { pixel_size = 22, valign = Gtk.Align.CENTER };
        top.append (icon_img);

        var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 1) { valign = Gtk.Align.CENTER };
        var title = new Gtk.Label ("Battery") { xalign = 0 };
        title.add_css_class ("cc-row-title");
        status_lbl = new Gtk.Label ("") { xalign = 0 };
        status_lbl.add_css_class ("cc-row-subtitle");
        text.append (title);
        text.append (status_lbl);
        top.append (text);

        top.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

        pct_lbl = new Gtk.Label ("") { valign = Gtk.Align.CENTER };
        pct_lbl.add_css_class ("cc-battery-pct");
        top.append (pct_lbl);

        root.append (top);

        if (pps.backend != PowerBackend.NONE) {
            seg = new SegmentedControl ();
            seg.segment_selected.connect ((i) => {
                if (i >= 0 && i < pps.available.length) pps.select (pps.available[i]);
            });
            root.append (seg);
            pps.state_changed.connect (refresh_profile);
        }

        service.state_changed.connect (refresh);
        refresh ();
        refresh_profile ();
    }

    public Gtk.Widget tile () { return root; }

    void refresh () {
        var raw = service.raw_status;
        string icon;
        if      (service.ac_online)              icon = "wired";
        else if (raw == "charging")              icon = "charging";
        else if (raw == "discharging" || raw.contains ("full")) {
            var p = service.percent;
            icon = p >= 70 ? "high" : p >= 30 ? "mid" : "low";
        } else                                   icon = "nobattery";
        icon_img.set_from_resource (CcStyle.icon (icon));

        pct_lbl.label = "%d%%".printf (service.percent);

        if      (raw == "charging")        status_lbl.label = "Charging";
        else if (raw == "discharging")     status_lbl.label = "On battery";
        else if (raw.contains ("full"))    status_lbl.label = "Full";
        else                               status_lbl.label = raw.length > 0 ? raw : "Unknown";
    }

    string profile_label (PowerProfile p) {
        switch (p) {
            case PowerProfile.PERFORMANCE: return "Performance";
            case PowerProfile.BALANCED:    return "Balanced";
            case PowerProfile.POWER_SAVER: return "Low Power";
            default:                       return "";
        }
    }

    void refresh_profile () {
        if (seg == null || pps.backend == PowerBackend.NONE) return;
        string[] labels = {};
        int selected = -1;
        for (int i = 0; i < pps.available.length; i++) {
            labels += profile_label (pps.available[i]);
            if (pps.available[i] == pps.current) selected = i;
        }
        seg.set_segments (labels);
        seg.set_selected (selected);
    }
}
