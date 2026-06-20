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

    // Tray applet layout, from the [tray] section of panel.ini (written by
    // lumen-settings). tray_order is the full ordered list of applet ids;
    // tray_disabled is the subset toggled off. An absent [tray] section leaves
    // tray_order at the catalog default and tray_disabled empty — byte-for-byte
    // identical to the old hardcoded tray. tray_enabled_order() resolves the two
    // against the shared catalog into what make_tray() actually builds.
    public static string[] tray_order = {};
    public static string[] tray_disabled = {};

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

        tray_order    = parse_id_list(Ini.get_value(ini, "tray", "order"));
        tray_disabled = parse_id_list(Ini.get_value(ini, "tray", "disabled"));
        // No [tray] order ⇒ fall back to the catalog's canonical order.
        if (tray_order.length == 0) {
            string[] defaults = {};
            foreach (var info in LumenTray.CATALOG) defaults += info.id;
            tray_order = defaults;
        }
    }

    // Comma-split, strip, drop empties. null/empty ⇒ empty array.
    static string[] parse_id_list (string? s) {
        string[] result = {};
        if (s == null) return result;
        foreach (var tok in s.split(",")) {
            var t = tok.strip();
            if (t != "") result += t;
        }
        return result;
    }

    // The resolved, enabled, ordered ids make_tray() iterates: start from
    // tray_order, append any catalog ids not already present (so a new built-in
    // applet appears after an upgrade without rewriting the config), drop the
    // disabled subset, and drop any id not in the catalog (stale/unknown).
    public static string[] tray_enabled_order () {
        var order = new Gee.ArrayList<string>();
        foreach (var id in tray_order) order.add(id);
        foreach (var info in LumenTray.CATALOG) {
            if (!order.contains(info.id)) order.add(info.id);
        }

        string[] result = {};
        foreach (var id in order) {
            if (id in tray_disabled) continue;
            if (!catalog_has(id)) continue;
            result += id;
        }
        return result;
    }

    static bool catalog_has (string id) {
        foreach (var info in LumenTray.CATALOG) {
            if (info.id == id) return true;
        }
        return false;
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
