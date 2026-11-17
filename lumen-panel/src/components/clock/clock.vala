public class Clock : Gtk.Box, Lumen.TrayApplet {

    Gtk.Label label;
    uint      timer = 0;

    public Clock (LogindBridge logind) {
        GLib.Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class("clock");

        label = new Gtk.Label(format_now()) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };
        label.add_css_class("clock-label");
        append(label);

        // GLib timeouts pause during suspend, so resync on resume. Connected only
        // while realized: the bridge is shared and outlives this applet.
        ulong sleep_id = 0;
        realize.connect(() => {
            sleep_id = logind.prepare_for_sleep.connect(on_sleep);
            schedule();
        });
        unrealize.connect(() => {
            SignalHandler.disconnect(logind, sleep_id);
            if (timer != 0) GLib.Source.remove(timer);
            timer = 0;
        });
    }

    void on_sleep (bool starting) {
        if (starting || timer == 0) return;
        GLib.Source.remove(timer);
        label.label = format_now();
        schedule();
    }

    // Ticks on minute boundaries.
    void schedule () {
        uint ms = 1000;
        if (!shows_seconds(PanelConfig.clock_format)) {
            var now = new DateTime.now_local();
            ms = (uint) (60000 - now.get_second() * 1000 - now.get_microsecond() / 1000);
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
