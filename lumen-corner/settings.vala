// lumen-corner-settings: edits config.ini; the running overlay reloads on save.
const int ARC_RADIUS = 200;
const int SLOT_BUTTON = 60;
const int ARC_SIZE = ARC_RADIUS + SLOT_BUTTON;
const string[] BACKGROUNDS = { "#eee", "transparent" };
const string[] BACKGROUND_LABELS = { "White", "Transparent", "Custom" };

class SettingsWindow : Gtk.ApplicationWindow {
    Config config;
    Gtk.Button[] slot_buttons = {};
    Gtk.ColorDialogButton color_button;

    public SettingsWindow(Gtk.Application app) {
        Object(application: app, title: "Lumen Corner", resizable: false);
        config = Config.load();

        var grid = new Gtk.Grid() {
            row_spacing = 12, column_spacing = 12,
            margin_top = 18, margin_bottom = 18, margin_start = 18, margin_end = 18,
        };
        grid.attach(new Gtk.Label("Size") { xalign = 0 }, 0, 0);
        grid.attach(build_size_picker(), 1, 0, 2);
        grid.attach(new Gtk.Label("Background") { xalign = 0 }, 0, 1);
        grid.attach(build_background_picker(), 1, 1);
        grid.attach(color_button, 2, 1);
        grid.attach(new Gtk.Label("Apps") { xalign = 0, yalign = 0 }, 0, 2);
        grid.attach(build_slot_arc(), 1, 2, 2);
        child = grid;
    }

    Gtk.Widget build_size_picker() {
        var picker = new Gtk.DropDown.from_strings(Config.SIZES);
        for (uint i = 0; i < Config.SIZES.length; i++) {
            if (Config.SIZES[i] == config.size) picker.selected = i;
        }
        picker.notify["selected"].connect(() => {
            config.size = Config.SIZES[picker.selected];
            save();
        });
        return picker;
    }

    Gtk.Widget build_background_picker() {
        var picker = new Gtk.DropDown.from_strings(BACKGROUND_LABELS);
        color_button = new Gtk.ColorDialogButton(new Gtk.ColorDialog() { with_alpha = true });
        color_button.rgba = Style.parse_color(config.background);
        uint custom = BACKGROUNDS.length;
        picker.selected = custom;
        for (uint i = 0; i < BACKGROUNDS.length; i++) {
            if (BACKGROUNDS[i] == config.background) picker.selected = i;
        }
        color_button.sensitive = picker.selected == custom;

        picker.notify["selected"].connect(() => {
            bool is_custom = picker.selected == custom;
            color_button.sensitive = is_custom;
            config.background = is_custom ? picked_color() : BACKGROUNDS[picker.selected];
            save();
        });
        color_button.notify["rgba"].connect(() => {
            if (picker.selected != custom) return;
            config.background = picked_color();
            save();
        });
        return picker;
    }

    // Laid out like the real ring: slot 0 at the bottom, slot 3 at the top.
    Gtk.Widget build_slot_arc() {
        var arc = new Gtk.Fixed();
        arc.set_size_request(ARC_SIZE, ARC_SIZE);
        double step = (Math.PI / 2) / Config.SLOT_COUNT;
        for (int i = 0; i < Config.SLOT_COUNT; i++) {
            var button = new Gtk.Button();
            button.set_size_request(SLOT_BUTTON, SLOT_BUTTON);
            int slot = i;
            button.clicked.connect(() => choose_app(slot));
            double angle = step * (i + 0.5);
            double center_x = SLOT_BUTTON / 2 + Math.cos(angle) * ARC_RADIUS;
            double center_y = ARC_SIZE - SLOT_BUTTON / 2 - Math.sin(angle) * ARC_RADIUS;
            arc.put(button, center_x - SLOT_BUTTON / 2, center_y - SLOT_BUTTON / 2);
            slot_buttons += button;
            show_slot(i);
        }
        return arc;
    }

    void show_slot(int slot) {
        var button = slot_buttons[slot];
        var info = config.slots[slot] == "" ? null : new DesktopAppInfo(config.slots[slot]);
        if (info == null) {
            button.child = new Gtk.Image.from_icon_name("list-add-symbolic") { pixel_size = 24 };
            button.tooltip_text = "Add app";
            return;
        }
        button.child = new Gtk.Image.from_gicon(info.get_icon() ?? new ThemedIcon("application-x-executable")) { pixel_size = 40 };
        button.tooltip_text = info.get_display_name();
    }

    void choose_app(int slot) {
        var chooser = new AppChooser(this, config.slots[slot] != "");
        chooser.chosen.connect((id) => {
            config.slots[slot] = id;
            show_slot(slot);
            save();
        });
        chooser.present();
    }

    // The vapi's rgba getter emits a call with the wrong arity; read the property instead.
    string picked_color() {
        Gdk.RGBA? color = null;
        color_button.get("rgba", out color);
        return color.to_string();
    }

    void save() {
        try {
            config.save();
        } catch (Error e) {
            warning("saving %s: %s", Config.file().get_path(), e.message);
        }
    }
}

// Searchable list of installed apps. Emits chosen("") for "Remove".
class AppChooser : Gtk.Window {
    public signal void chosen(string desktop_id);

    public AppChooser(Gtk.Window parent, bool removable) {
        Object(transient_for: parent, modal: true, title: "Choose app", default_width: 360, default_height: 480);

        var search = new Gtk.SearchEntry();
        var list = new Gtk.ListBox() { activate_on_single_click = true };
        foreach (var info in sorted_apps()) list.append(new AppRow(info));
        list.set_filter_func((row) => {
            var needle = search.text.casefold();
            return needle == "" || needle in ((AppRow) row).info.get_display_name().casefold();
        });
        search.search_changed.connect(() => list.invalidate_filter());
        list.row_activated.connect((row) => pick(((AppRow) row).info.get_id()));

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6) {
            margin_top = 12, margin_bottom = 12, margin_start = 12, margin_end = 12,
        };
        box.append(search);
        box.append(new Gtk.ScrolledWindow() { child = list, vexpand = true });
        if (removable) {
            var remove = new Gtk.Button.with_label("Remove from slot");
            remove.clicked.connect(() => pick(""));
            box.append(remove);
        }
        child = box;
    }

    void pick(string desktop_id) {
        chosen(desktop_id);
        destroy();
    }

    static List<AppInfo> sorted_apps() {
        var apps = new List<AppInfo>();
        foreach (var info in AppInfo.get_all()) {
            if (info.should_show()) apps.insert_sorted(info, (a, b) => a.get_display_name().collate(b.get_display_name()));
        }
        return apps;
    }
}

class AppRow : Gtk.ListBoxRow {
    public AppInfo info;

    public AppRow(AppInfo info) {
        this.info = info;
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10) { margin_top = 4, margin_bottom = 4, margin_start = 6 };
        box.append(new Gtk.Image.from_gicon(info.get_icon() ?? new ThemedIcon("application-x-executable")) { pixel_size = 24 });
        box.append(new Gtk.Label(info.get_display_name()));
        child = box;
    }
}

int main(string[] args) {
    var app = new Gtk.Application("io.github.LumenCorner.Settings", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect(() => {
        (app.active_window ?? new SettingsWindow(app)).present();
    });
    return app.run(args);
}
