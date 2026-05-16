using Gtk;

public class WifiRow : Gtk.ListBoxRow {

    public string ssid { get; private set; }
    public int signal_pct { get; private set; }
    public bool is_secured { get; private set; }
    public bool is_connected { get; set; }

    public WifiRow (WifiNet net, bool is_connected) {
        this.ssid = net.ssid;
        this.signal_pct = net.signal;
        this.is_secured = net.security != "" && net.security != "--";
        this.is_connected = is_connected;

        var hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) {
            margin_start = 4, margin_end = 4,
            margin_top = 6, margin_bottom = 6,
        };

        var bars = new SignalBars(net.signal);
        hbox.append(bars);

        var label = new Gtk.Label(net.ssid) {
            xalign = 0, hexpand = true,
            ellipsize = Pango.EllipsizeMode.END,
        };
        hbox.append(label);

        if (this.is_secured) {
            var lock_icon = new Gtk.Image.from_icon_name("system-lock-screen-symbolic") {
                pixel_size = 14,
            };
            lock_icon.add_css_class("dim-label");
            hbox.append(lock_icon);
        }

        if (is_connected) {
            var ok = new Gtk.Image.from_icon_name("emblem-ok-symbolic") {
                pixel_size = 14,
            };
            hbox.append(ok);
        }

        set_child(hbox);
    }
}
