using Gtk;

public class SoundPage : Gtk.Box {

    SoundService service;
    Gtk.Scale  scale;
    Gtk.Button mute_button;
    Gtk.ListBox sink_list;
    bool suppress_scale = false;

    public SoundPage (SoundService service) {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);
        this.service = service;
        add_css_class("sound-page");
        set_size_request(360, 240);

        var title = new Gtk.Label("Sound") { xalign = 0 };
        title.add_css_class("page-title");
        append(title);

        var slider_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
            hexpand = true,
        };
        mute_button = new Gtk.Button.from_icon_name("audio-volume-high-symbolic");
        mute_button.add_css_class("flat");
        mute_button.clicked.connect(() => service.toggle_mute());
        slider_row.append(mute_button);

        scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1) {
            hexpand = true,
            draw_value = false,
        };
        scale.value_changed.connect(() => {
            if (suppress_scale) return;
            service.change_volume((int) scale.get_value());
        });
        slider_row.append(scale);
        append(slider_row);

        var sinks_title = new Gtk.Label("Output") { xalign = 0, margin_top = 6 };
        sinks_title.add_css_class("stat-label");
        append(sinks_title);

        sink_list = new Gtk.ListBox() {
            selection_mode = Gtk.SelectionMode.SINGLE,
            hexpand = true,
        };
        sink_list.add_css_class("sink-list");
        sink_list.row_activated.connect((row) => {
            unowned string? id = row.get_data<string?>("sink-id");
            if (id != null) service.change_default_sink(id);
        });
        var sink_scroll = new Gtk.ScrolledWindow() {
            child = sink_list,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
            vexpand = true,
            min_content_height = 100,
        };
        append(sink_scroll);

        service.state_changed.connect(refresh);
        refresh();
    }

    void refresh () {
        suppress_scale = true;
        scale.set_value(service.volume_percent);
        suppress_scale = false;
        mute_button.set_icon_name(service.muted
            ? "audio-volume-muted-symbolic"
            : "audio-volume-high-symbolic");

        // Rebuild sink list (small N, infrequent).
        Gtk.Widget? r;
        while ((r = sink_list.get_first_child()) != null) sink_list.remove(r);

        foreach (var s in service.sinks) {
            var row = new Gtk.ListBoxRow();
            var lbl = new Gtk.Label(s.name) { xalign = 0, hexpand = true };
            row.set_child(lbl);
            row.set_data<string?>("sink-id", s.id);
            sink_list.append(row);
            if (s.id == service.default_sink) sink_list.select_row(row);
        }
    }
}
