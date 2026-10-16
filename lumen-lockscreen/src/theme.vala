// Theme — static config for lumen-lockscreen. Exposes typed fields for code
// (colors as Gdk.RGBA, sizes as int, flags as bool) AND a generate_root_css()
// that emits @define-color tokens so the stock GTK widgets on the card
// (Gtk.PasswordEntry, buttons) pick up the palette.
public class Theme {
    // Theme is never instantiated, so non-const static initializers (emitted
    // into class_init) would never run; load() assigns every field instead.
    public static Gdk.RGBA text;              // primary text (clock, name)
    public static Gdk.RGBA muted_text;        // date, hints
    public static Gdk.RGBA entry_background;
    public static Gdk.RGBA entry_error;
    public static Gdk.RGBA scrim;             // tint over the blurred desktop snapshot

    public static string background_image;    // fallback when no snapshot ("" = solid)
    public static int    clock_font_size;
    public static int    date_font_size;
    public static int    avatar_size;
    public static int    blur_radius;         // light GSK frost over the wallpaper
    public static int    idle_timeout_ms;     // ext-idle-notify-v1; 0 disables auto-lock
    public static int    failure_backoff_ms;
    public static bool   show_power_menu;

    public static void load() {
        var t = new LumenCommon.ThemeJson(Utils.THEME_FILE);
        text               = t.get_color("lockscreen.text", "rgba(255,255,255,1)");
        muted_text         = t.get_color("lockscreen.muted-text", "rgba(90%,90%,94%,0.75)");
        // Apple-style translucent-white password pill on a blurred backdrop.
        entry_background   = t.get_color("lockscreen.entry-background", "rgba(255,255,255,0.18)");
        entry_error        = t.get_color("lockscreen.entry-error", "rgba(95%,42%,42%,1)");
        scrim              = t.get_color("lockscreen.scrim", "rgba(0,0,0,0.35)");
        background_image   = t.get_str("lockscreen.background-image", "");
        clock_font_size    = t.get_int("lockscreen.clock-font-size", 96);
        date_font_size     = t.get_int("lockscreen.date-font-size", 18);
        avatar_size        = t.get_int("lockscreen.avatar-size", 256);
        blur_radius        = t.get_int("lockscreen.blur-radius", 12);
        idle_timeout_ms    = t.get_int("lockscreen.idle-timeout-ms", 300000);
        failure_backoff_ms = t.get_int("lockscreen.failure-backoff-ms", 3000);
        show_power_menu    = t.get_bool("lockscreen.show-power-menu", true);
    }

    // @define-color tokens consumed by res/style.css for the stock widgets.
    public static string generate_root_css() {
        return ("@define-color lockscreen_text %s;\n"             +
                "@define-color lockscreen_muted_text %s;\n"       +
                "@define-color lockscreen_entry_background %s;\n" +
                "@define-color lockscreen_entry_error %s;\n").printf(
                    text.to_string(), muted_text.to_string(),
                    entry_background.to_string(), entry_error.to_string());
    }
}
