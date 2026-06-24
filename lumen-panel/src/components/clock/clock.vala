using Gtk;

public class Clock : Gtk.Box, ITrayApplet {

    Gtk.Label label;

    public Clock () {
        GLib.Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        add_css_class("clock");

        label = new Gtk.Label(format_now()) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };
        label.add_css_class("clock-label");
        append(label);

        GLib.Timeout.add_seconds(1, () => {
            label.label = format_now();
            return Source.CONTINUE;
        });
    }

    static string format_now () {
        return new DateTime.now_local().format(PanelConfig.clock_format);
    }

    // Icon-only applet: the clock IS its own tray widget, no control module.
    public Gtk.Widget  tray_widget () { return this; }
}
