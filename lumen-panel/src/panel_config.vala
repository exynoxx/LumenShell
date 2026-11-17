// Read once at startup from panel.json (flat dotted keys, written by lumen-settings).
public class PanelConfig {
    public static bool at_top = false;

    public enum OpenIndicator { SHADE, DOT, TICKS, PIP, EMBER, SEGMENTS, DIM_CLOSED, GLASS, ROUND, NONE }
    public static OpenIndicator open_indicator = OpenIndicator.SHADE;

    public enum ActiveIndicator { UNDERLINE, PILL, TINT, CARET, COLUMN, SPLIT, SUNSHINE, GLASS, CIRCLE }
    public static ActiveIndicator active_indicator = ActiveIndicator.UNDERLINE;

    public enum HoverStyle { FLAT, CHIP, LIFT }
    public static HoverStyle hover_style = HoverStyle.FLAT;

    // per_monitor_apps: each panel's taskbar shows only its own monitor's windows.
    public static bool multi_monitor = false;
    public static bool per_monitor_apps = false;
    // With multi_monitor, secondary panels get their own full tray too.
    public static bool tray_all_monitors = false;

    // Only effective in a PANEL_PEEK build.
    public static bool show_launcher = false;

    // Kept in sync with the lumen-settings panel page default.
    public const string DEFAULT_CLOCK_FORMAT = "%a %d %b  %H:%M";
    public static string clock_format = DEFAULT_CLOCK_FORMAT;

    // Resolved into PanelWindow.Mode there; behavior_auto_hide is the legacy
    // fallback when behavior.mode is absent.
    public static string? behavior_mode = null;
    public static bool behavior_auto_hide = false;

    public static string[] tray_order = {};
    public static string[] tray_disabled = {};

    public static void load () {
        var cfg = new LumenCommon.ThemeJson(LumenCommon.Paths.panel_json());

        at_top            = cfg.get_str("position", "") == "top";
        open_indicator    = parse_indicator(cfg.get_str("app.open-indicator", ""));
        active_indicator  = parse_active_indicator(cfg.get_str("app.active-indicator", ""));
        hover_style       = parse_hover_style(cfg.get_str("app.hover-style", ""));
        multi_monitor     = cfg.get_bool("behavior.multi-monitor", false);
        per_monitor_apps  = cfg.get_bool("behavior.per-monitor-apps", false);
        tray_all_monitors = cfg.get_bool("behavior.tray-all-monitors", false);
        show_launcher     = cfg.get_bool("app.launcher-button", false);
        var fmt = cfg.get_str("clock.format", "");
        if (fmt.strip() != "") clock_format = fmt;

        // Absent (null) and present-but-unrecognised mean different things here:
        // only an absent key falls back to the legacy auto-hide bool.
        behavior_mode      = cfg.has("behavior.mode") ? cfg.get_str("behavior.mode", "") : null;
        behavior_auto_hide = cfg.get_bool("behavior.auto-hide", false);

        tray_order    = cfg.get_str_array("tray.order");
        tray_disabled = cfg.get_str_array("tray.disabled");
        if (tray_order.length == 0) {
            string[] defaults = {};
            foreach (var info in LumenTray.CATALOG) defaults += info.id;
            tray_order = defaults;
        }
    }

    // tray_order plus any catalog ids it lacks (so new applets appear after an
    // upgrade), minus disabled and unknown ids.
    public static string[] tray_enabled_order () {
        var order = new Gee.ArrayList<string>();
        foreach (var id in tray_order) order.add(id);
        // A missing id goes right after its catalog predecessor, not at the end.
        int at = 0;
        foreach (var info in LumenTray.CATALOG) {
            int i = order.index_of(info.id);
            if (i < 0) order.insert(at, info.id); else at = i;
            at++;
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
            case "ticks":   return OpenIndicator.TICKS;
            case "pip":     return OpenIndicator.PIP;
            case "ember":   return OpenIndicator.EMBER;
            case "segments":   return OpenIndicator.SEGMENTS;
            case "dim-closed": return OpenIndicator.DIM_CLOSED;
            case "glass":   return OpenIndicator.GLASS;
            case "round":   return OpenIndicator.ROUND;
            case "none":    return OpenIndicator.NONE;
            default:        return OpenIndicator.SHADE;
        }
    }

    static ActiveIndicator parse_active_indicator (string? s) {
        switch (s) {
            case "pill":      return ActiveIndicator.PILL;
            case "tint":      return ActiveIndicator.TINT;
            case "caret":     return ActiveIndicator.CARET;
            case "column":    return ActiveIndicator.COLUMN;
            case "split":     return ActiveIndicator.SPLIT;
            case "sunshine":  return ActiveIndicator.SUNSHINE;
            case "glass":     return ActiveIndicator.GLASS;
            case "circle":    return ActiveIndicator.CIRCLE;
            case "underline": return ActiveIndicator.UNDERLINE;
            default:          return ActiveIndicator.UNDERLINE;
        }
    }

    static HoverStyle parse_hover_style (string? s) {
        switch (s) {
            case "chip": return HoverStyle.CHIP;
            case "lift": return HoverStyle.LIFT;
            default:     return HoverStyle.FLAT;
        }
    }
}
