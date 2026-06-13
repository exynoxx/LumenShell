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

    public static void load () {
        var ini = Environment.get_user_config_dir() + "/lumen-shell/panel.ini";
        at_top = Ini.get_key_value(ini, "position") == "top";
        open_indicator = parse_indicator(Ini.get_key_value(ini, "app.open-indicator"));
        multi_monitor    = Ini.get_key_value(ini, "behavior.multi-monitor")    == "true";
        per_monitor_apps = Ini.get_key_value(ini, "behavior.per-monitor-apps") == "true";
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
