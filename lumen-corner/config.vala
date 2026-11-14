// The on-disk settings shared by the overlay and the settings app.
public class Config {
    public const int SLOT_COUNT = 4;
    public const string DEFAULT_BACKGROUND = "#eee";
    public const string[] SIZES = { "small", "medium", "large" };

    const string[] DEFAULT_APPS = {
        "org.gnome.Nautilus.desktop", "firefox.desktop",
        "org.gnome.Terminal.desktop", "org.gnome.Settings.desktop",
        "org.gnome.Ptyxis.desktop", "kitty.desktop", "foot.desktop",
    };

    public string size = "medium";
    public string background = DEFAULT_BACKGROUND;
    // Desktop IDs, slot 0 at the bottom of the ring; "" is an empty slot.
    public string[] slots;

    public static File file() {
        return File.new_for_path(Path.build_filename(Environment.get_user_config_dir(), "lumen-corner", "config.ini"));
    }

    public static Config load() {
        var config = new Config();
        config.slots = installed_defaults();
        var kf = new KeyFile();
        try {
            kf.load_from_file(file().get_path(), KeyFileFlags.NONE);
        } catch (Error e) {
            return config;
        }
        config.size = read(kf, "style", "size") ?? config.size;
        config.background = read(kf, "style", "background") ?? config.background;
        try {
            var stored = kf.get_string_list("apps", "slots");
            for (int i = 0; i < SLOT_COUNT; i++) config.slots[i] = i < stored.length ? stored[i].strip() : "";
        } catch (Error e) {}
        return config;
    }

    public void save() throws Error {
        var kf = new KeyFile();
        kf.set_string("style", "size", size);
        kf.set_string("style", "background", background);
        kf.set_string_list("apps", "slots", slots);
        DirUtils.create_with_parents(file().get_parent().get_path(), 0755);
        kf.save_to_file(file().get_path());
    }

    static string[] installed_defaults() {
        string[] slots = {};
        foreach (var id in DEFAULT_APPS) {
            if (slots.length < SLOT_COUNT && new DesktopAppInfo(id) != null) slots += id;
        }
        while (slots.length < SLOT_COUNT) slots += "";
        return slots;
    }

    static string? read(KeyFile kf, string group, string key) {
        try {
            return kf.get_string(group, key).strip();
        } catch (Error e) {
            return null;
        }
    }
}

// Ring geometry and colour derived from a Config.
public struct Style {
    public int outer_radius;
    public int inner_radius;
    public int icon_size;
    public Gdk.RGBA background;

    public Style(Config config) {
        switch (config.size) {
        case "small": outer_radius = 180; inner_radius = 105; icon_size = 32; break;
        case "large": outer_radius = 320; inner_radius = 187; icon_size = 52; break;
        default:
            if (config.size != "medium") warning("config.ini: unknown size '%s', using medium", config.size);
            outer_radius = 240; inner_radius = 140; icon_size = 40;
            break;
        }
        background = parse_color(config.background);
    }

    public static Gdk.RGBA parse_color(string text) {
        var color = Gdk.RGBA();
        // Gdk.RGBA.parse rejects the CSS keyword "transparent".
        if (text == "transparent") return color;
        if (!color.parse(text)) {
            warning("config.ini: bad background '%s', using %s", text, Config.DEFAULT_BACKGROUND);
            color.parse(Config.DEFAULT_BACKGROUND);
        }
        return color;
    }
}
