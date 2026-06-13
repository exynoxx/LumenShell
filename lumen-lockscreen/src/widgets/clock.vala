using Gtk;

// Big time + date cluster, updated once a second. Stock labels with Pango
// absolute sizing from the theme (Pango.attr_size_new doesn't exist in the
// vapi — use AttrSize.new_absolute, per the repo-wide quirk note).
public class ClockWidget : Gtk.Box {

    private Gtk.Label time_label;
    private Gtk.Label date_label;
    private uint tick_source = 0;

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
        // Re-tick aligned to the next wall-clock second would be nicer, but a
        // 1 s timer is plenty for a lock face and matches the OSD's simplicity.
        tick_source = Timeout.add_seconds(1, () => { update(); return Source.CONTINUE; });
    }

    ~ClockWidget() {
        if (tick_source != 0) Source.remove(tick_source);
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
