using Gtk;

public class BatteryPage : Gtk.Box {

    BatteryService service;

    Gtk.Label   pct_label;
    Gtk.Label   status_label;
    Gtk.LevelBar bar;
    Gtk.Label   voltage_label;
    Gtk.Label   current_label;
    Gtk.Label   charge_label;
    Gtk.Label   time_label;

    public BatteryPage (BatteryService service) {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);
        this.service = service;
        add_css_class("battery-page");
        set_size_request(360, 240);

        var title = new Gtk.Label("Battery") { xalign = 0 };
        title.add_css_class("page-title");
        append(title);

        pct_label = new Gtk.Label("—") { xalign = 0.5f };
        pct_label.add_css_class("battery-pct");
        append(pct_label);

        status_label = new Gtk.Label("—") { xalign = 0.5f };
        status_label.add_css_class("page-status");
        append(status_label);

        bar = new Gtk.LevelBar.for_interval(0, 100) { hexpand = true };
        bar.add_offset_value("low",  25);
        bar.add_offset_value("high", 60);
        bar.add_offset_value("full", 95);
        append(bar);

        var stats = new Gtk.Grid() {
            column_spacing = 24,
            row_spacing = 6,
            margin_top = 8,
        };
        voltage_label = new_stat_value();
        current_label = new_stat_value();
        charge_label  = new_stat_value();
        time_label    = new_stat_value();
        stats.attach(new_stat_label("Voltage"), 0, 0, 1, 1);
        stats.attach(voltage_label,             0, 1, 1, 1);
        stats.attach(new_stat_label("Current"), 1, 0, 1, 1);
        stats.attach(current_label,             1, 1, 1, 1);
        stats.attach(new_stat_label("Charge"),  0, 2, 1, 1);
        stats.attach(charge_label,              0, 3, 1, 1);
        stats.attach(new_stat_label("Est. time"), 1, 2, 1, 1);
        stats.attach(time_label,                1, 3, 1, 1);
        append(stats);

        service.state_changed.connect(refresh);
        refresh();
    }

    static Gtk.Label new_stat_label (string text) {
        var l = new Gtk.Label(text) { xalign = 0 };
        l.add_css_class("stat-label");
        return l;
    }
    static Gtk.Label new_stat_value () {
        var l = new Gtk.Label("—") { xalign = 0 };
        l.add_css_class("stat-value");
        return l;
    }

    void refresh () {
        pct_label.label = "%d%%".printf(service.percent);
        bar.value = service.percent;

        var raw = service.raw_status;
        if (raw == "charging")           status_label.label = "⚡ Charging";
        else if (raw == "discharging")   status_label.label = "Discharging";
        else if (raw.contains("full"))   status_label.label = "✓ Full";
        else                             status_label.label = raw == "" ? "Unknown" : raw;

        voltage_label.label = "%.2f V".printf(service.voltage_v);
        current_label.label = "%.2f A".printf(service.current_a);
        charge_label.label  = "%d / %d mAh".printf(
            service.charge_now / 1000, service.charge_full / 1000);

        if ((raw == "discharging" || raw == "charging") && service.current_a > 0.05f) {
            float hrs;
            string suffix;
            if (raw == "discharging") {
                hrs = (service.charge_now / 1000000f) / service.current_a;
                suffix = "left";
            } else {
                hrs = ((service.charge_full - service.charge_now) / 1000000f) / service.current_a;
                suffix = "to full";
            }
            int h = (int) hrs;
            int m = (int)((hrs - h) * 60);
            time_label.label = h > 0
                ? "%dh %dm %s".printf(h, m, suffix)
                : "%dm %s".printf(m, suffix);
        } else {
            time_label.label = "—";
        }
    }
}
