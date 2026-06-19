using GLib;

// Global panel placement, read once at startup from panel.ini. Widgets that
// must mirror their layout when the panel sits at the top of the screen
// (popover direction, tray growth, the backdrop strip's edge) consult
// PanelConfig.at_top rather than threading the flag through every constructor.
public class PanelConfig {
    public static bool at_top = false;

    // How a taskbar entry signals it has open windows but isn't focused, so a
    // running app is distinguishable from a pinned-but-closed one. Read once at
    // startup; AppEntry.snapshot() branches on it. SHADE is the default.
    public enum OpenIndicator { SHADE, DOT, CORNERS, GLASS, NONE }
    public static OpenIndicator open_indicator = OpenIndicator.SHADE;

    // Multi-monitor: when true a panel is placed on every connected output.
    // per_monitor_apps (a sub-option) makes each panel's taskbar show only the
    // windows on its own monitor.
    public static bool multi_monitor = false;
    public static bool per_monitor_apps = false;
    // When true (and multi_monitor is on) every secondary panel also shows the
    // tray area — minus the system-tray (SNI) icons, which stay on the host.
    public static bool tray_all_monitors = false;

    // When true a persistent launcher button (app glyph) sits at the left edge
    // of the panel; clicking it toggles the app-drawer reveal (curtain/slide
    // peek). Only effective in a PANEL_PEEK build.
    public static bool show_launcher = false;

    // strftime pattern the clock renders with. The default writes the weekday
    // with letters (e.g. "Sat 13 Jun  14:30"). Kept in sync with the
    // lumen-settings panel page default.
    public const string DEFAULT_CLOCK_FORMAT = "%a %d %b  %H:%M";
    public static string clock_format = DEFAULT_CLOCK_FORMAT;

    public static void load () {
        var ini = Environment.get_user_config_dir() + "/lumen-shell/panel.ini";
        at_top = Ini.get_value(ini, "panel", "position") == "top";
        open_indicator = parse_indicator(Ini.get_value(ini, "panel", "app.open-indicator"));
        multi_monitor    = Ini.get_value(ini, "panel", "behavior.multi-monitor")    == "true";
        per_monitor_apps = Ini.get_value(ini, "panel", "behavior.per-monitor-apps") == "true";
        tray_all_monitors = Ini.get_value(ini, "panel", "behavior.tray-all-monitors") == "true";
        show_launcher    = Ini.get_value(ini, "panel", "app.launcher-button")       == "true";
        var fmt = Ini.get_value(ini, "panel", "clock.format");
        if (fmt != null && fmt.strip() != "") clock_format = fmt;
    }

    static OpenIndicator parse_indicator (string? s) {
        switch (s) {
            case "dot":     return OpenIndicator.DOT;
            case "corners": return OpenIndicator.CORNERS;
            case "glass":   return OpenIndicator.GLASS;
            case "none":    return OpenIndicator.NONE;
            default:        return OpenIndicator.SHADE;
        }
    }
}
