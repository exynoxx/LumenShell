public class ClockWidget : Gtk.Box {

    private Gtk.Label time_label;
    private Gtk.Label date_label;
    private uint tick_source = 0;
    private uint sleep_sub = 0;

    public ClockWidget() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
        set_halign(Gtk.Align.CENTER);

        time_label = new Gtk.Label("") {
            halign = Gtk.Align.CENTER,
        };
        time_label.add_css_class("lockscreen-clock");
        time_label.attributes = sized_bold(Theme.clock_font_size);

        date_label = new Gtk.Label("") {
            halign = Gtk.Align.CENTER,
        };
        date_label.add_css_class("lockscreen-date");
        date_label.attributes = sized(Theme.date_font_size);

        append(time_label);
        append(date_label);

        update();
    }

    // The tick closure holds a ref on `this`, so it must stop on unrealize
    // or the widget (and timer) outlives its lock window.
    public override void realize() {
        base.realize();
        tick();
        // GLib timers run on CLOCK_MONOTONIC, which stops during suspend, so the
        // minute-aligned tick would be up to a minute stale on resume — and the
        // lock screen is exactly what is showing then. Re-sync on wake.
        try {
            sleep_sub = Bus.get_sync(BusType.SYSTEM).signal_subscribe(
                "org.freedesktop.login1", "org.freedesktop.login1.Manager",
                "PrepareForSleep", "/org/freedesktop/login1", null,
                DBusSignalFlags.NONE, (c, s, p, i, n, args) => {
                    if (!args.get_child_value(0).get_boolean()) tick();
                });
        } catch (Error e) {}
    }

    public override void unrealize() {
        if (tick_source != 0) { Source.remove(tick_source); tick_source = 0; }
        if (sleep_sub != 0) {
            try { Bus.get_sync(BusType.SYSTEM).signal_unsubscribe(sleep_sub); } catch (Error e) {}
            sleep_sub = 0;
        }
        base.unrealize();
    }

    // The labels only change per minute, so wake once at the next boundary.
    private void tick() {
        update();
        if (tick_source != 0) Source.remove(tick_source);
        var now = new DateTime.now_local();
        uint ms = 60000 - (uint) (now.get_second() * 1000 + now.get_microsecond() / 1000);
        tick_source = Timeout.add(ms + 50, () => { tick_source = 0; tick(); return Source.REMOVE; });
    }

    private void update() {
        var now = new DateTime.now_local();
        time_label.label = now.format("%H:%M");
        date_label.label = now.format("%A, %-d %B %Y");
    }

    private static Pango.AttrList sized(int pt) {
        var l = new Pango.AttrList();
        l.insert(Pango.AttrSize.new_absolute(pt * Pango.SCALE));
        return l;
    }

    private static Pango.AttrList sized_bold(int pt) {
        var l = sized(pt);
        l.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
        return l;
    }
}
