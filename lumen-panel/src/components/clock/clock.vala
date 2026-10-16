public class Clock : Gtk.Box, ITrayApplet {

    Gtk.Label label;
    uint      timer = 0;

    public Clock () {
        GLib.Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class("clock");

        label = new Gtk.Label(format_now()) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };
        label.add_css_class("clock-label");
        append(label);

        realize.connect(schedule);
        unrealize.connect(() => {
            if (timer != 0) GLib.Source.remove(timer);
            timer = 0;
        });
    }

    // Ticks on minute boundaries, capped at 10 s: GLib timeouts pause during
    // suspend, so this bounds staleness after resume.
    void schedule () {
        uint ms = 1000;
        if (!shows_seconds(PanelConfig.clock_format)) {
            var now = new DateTime.now_local();
            ms = (uint) (60000 - now.get_second() * 1000 - now.get_microsecond() / 1000);
            ms = uint.min(ms, 10000);
        }
        timer = GLib.Timeout.add(ms + 5, () => {
            timer = 0;
            label.label = format_now();
            schedule();
            return Source.REMOVE;
        });
    }

    static bool shows_seconds (string fmt) {
        foreach (var t in new string[] { "%S", "%T", "%r", "%s", "%c", "%X" })
            if (fmt.contains(t)) return true;
        return false;
    }

    static string format_now () {
        return new DateTime.now_local().format(PanelConfig.clock_format);
    }

    public Gtk.Widget  tray_widget () { return this; }
}
