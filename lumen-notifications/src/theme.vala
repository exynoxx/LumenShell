public enum DismissStyle {
    SLIDE_RIGHT,
    FADE;

    public static DismissStyle? parse(string s) {
        switch (s) {
            case "slide-right": return SLIDE_RIGHT;
            case "fade":        return FADE;
            default:            return null;
        }
    }
}

public class Theme {
    // Theme is never instantiated, so non-const static initializers (emitted
    // into class_init) would never run; load() assigns every field instead.
    public static Gdk.RGBA banner_bg;
    public static Gdk.RGBA banner_border;
    public static Gdk.RGBA banner_text;
    public static Gdk.RGBA banner_subtext;
    public static Gdk.RGBA action_bg;
    public static Gdk.RGBA action_bg_hover;
    public static Gdk.RGBA action_text;
    public static int     clear_all_radius;

    public static int radius;
    public static int padding;
    public static int spacing;
    public static int width;
    public static int gap;
    public static int margin_top;
    public static int margin_right;

    // Duration of a banner's leave transition (BannerStack's Gtk.Revealer).
    public static int fade_out_ms;

    public static int expire_default_ms;

    public static DismissStyle dismiss_style;
    public static int          cascade_ms;
    public static int          clear_threshold;

    public static void load() {
        var t = new LumenCommon.ThemeJson(Utils.THEME_FILE);
        banner_bg         = t.get_color("banner.background", "rgba(7%,8%,12%,0.96)");
        banner_border     = t.get_color("banner.border", "rgba(255,255,255,0.12)");
        banner_text       = t.get_color("banner.text", "rgba(92%,92%,92%,1)");
        banner_subtext    = t.get_color("banner.subtext", "rgba(69%,69%,69%,1)");
        action_bg         = t.get_color("action.background", "rgba(255,255,255,0.08)");
        action_bg_hover   = t.get_color("action.background-hover", "rgba(255,255,255,0.16)");
        action_text       = t.get_color("action.text", "rgba(255,255,255,1)");
        radius            = t.get_int("banner.radius", 12);
        padding           = t.get_int("banner.padding", 14);
        spacing           = t.get_int("banner.spacing", 8);
        width             = t.get_int("banner.width", 360);
        gap               = t.get_int("banner.gap", 10);
        margin_top        = t.get_int("banner.margin.top", 16);
        margin_right      = t.get_int("banner.margin.right", 16);
        clear_all_radius  = t.get_int("clear-all.radius", 6);
        fade_out_ms       = t.get_int("animation.fade-out-ms", 800);
        expire_default_ms = t.get_int("expire.default-ms", 5000);
        cascade_ms        = t.get_int("dismiss.cascade-ms", 80);
        clear_threshold   = t.get_int("clear-all.threshold", 3);

        var style = t.get_str("dismiss.style", "slide-right");
        DismissStyle? d = DismissStyle.parse(style);
        if (d == null) warning("lumen-notifications: unknown dismiss.style: %s", style);
        dismiss_style = d ?? DismissStyle.SLIDE_RIGHT;
    }

    public static string generate_root_css() {
        return ".lumen-notif-root { background-color: transparent; }" +
               ".lumen-notif-title { font-weight: bold; color: %s; }".printf(banner_text.to_string()) +
               ".lumen-notif-body  { color: %s; }".printf(banner_subtext.to_string()) +
               generate_action_css() +
               generate_clear_all_css();
    }

    public static string generate_clear_all_css() {
        return ("""
        .lumen-notif-clear-all,
        .lumen-notif-clear-all:focus {
            background-color: %s;
            background-image: none;
            color: %s;
            border: 1px solid %s;
            border-radius: %dpx;
            padding: 8px 16px;
            min-height: 0;
            box-shadow: none;
            outline: none;
            text-shadow: none;
            font-weight: 600;
        }
        .lumen-notif-clear-all:hover  { background-color: %s; }
        .lumen-notif-clear-all:active { background-color: %s; }
        """).printf(
            Theme.banner_bg.to_string(),
            Theme.banner_text.to_string(),
            Theme.banner_border.to_string(),
            Theme.clear_all_radius,
            Theme.action_bg_hover.to_string(),
            Theme.action_bg.to_string()
        );
    }

    public static string generate_action_css() {
        // GNOME-shell-style flat action buttons:
        //   - transparent base, subtle hover
        //   - no per-button radius (parent's rounded clip handles the bottom
        //     corners; intermediate edges stay flat)
        //   - 1px separator between the body and the action row, and between
        //     adjacent buttons
        string sep = Theme.banner_border.to_string();
        return ("""
        .lumen-notif-actions {
            border-top: 1px solid %s;
        }
        .lumen-notif-action,
        .lumen-notif-action:focus {
            background-color: transparent;
            background-image: none;
            color: %s;
            border: none;
            border-radius: 0;
            padding: 10px 12px;
            min-height: 0;
            box-shadow: none;
            outline: none;
            text-shadow: none;
        }
        .lumen-notif-action:hover {
            background-color: %s;
        }
        .lumen-notif-action:active {
            background-color: %s;
        }
        .lumen-notif-action:not(:first-child) {
            border-left: 1px solid %s;
        }
        """).printf(
            sep,
            Theme.action_text.to_string(),
            Theme.action_bg_hover.to_string(),
            Theme.action_bg.to_string(),
            sep
        );
    }
}
