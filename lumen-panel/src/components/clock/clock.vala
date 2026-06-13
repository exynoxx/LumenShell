using Gtk;

public class Clock : Gtk.Box {

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
        return new DateTime.now_local().format("%Y-%m-%d  %H:%M:%S");
    }
}
