public struct Style {
    public int outer_radius;
    public int inner_radius;
    public int icon_size;
    public Gdk.RGBA background;

    const string DEFAULT_BACKGROUND = "#eee";

    public static Style load() {
        Style style = { 240, 140, 40, parse_color(DEFAULT_BACKGROUND) };
        var file = new KeyFile();
        try {
            file.load_from_file(Path.build_filename(Environment.get_user_config_dir(), "lumen-corner", "config.ini"), KeyFileFlags.NONE);
        } catch (Error e) {
            return style;
        }
        var size = read(file, "size");
        if (size != null) style.apply_size(size);
        var background = read(file, "background");
        if (background != null) style.background = parse_color(background);
        return style;
    }

    void apply_size(string size) {
        switch (size) {
        case "small":  outer_radius = 180; inner_radius = 105; icon_size = 32; break;
        case "medium": break;
        case "large":  outer_radius = 320; inner_radius = 187; icon_size = 52; break;
        default: warning("config.ini: unknown size '%s', using medium", size); break;
        }
    }

    static string? read(KeyFile file, string key) {
        try {
            return file.get_string("style", key).strip();
        } catch (Error e) {
            return null;
        }
    }

    static Gdk.RGBA parse_color(string text) {
        var color = Gdk.RGBA();
        // Gdk.RGBA.parse rejects the CSS keyword "transparent".
        if (text == "transparent") return color;
        if (!color.parse(text)) {
            warning("config.ini: bad background '%s', using %s", text, DEFAULT_BACKGROUND);
            color.parse(DEFAULT_BACKGROUND);
        }
        return color;
    }
}
