// Read once at startup from panel.json (flat dotted keys, written by lumen-settings).
public class PanelConfig {
    public static bool at_top = false;

    public enum OpenIndicator { SHADE, DOT, CORNERS, GLASS, ROUND, NONE }
    public static OpenIndicator open_indicator = OpenIndicator.SHADE;

    public enum ActiveIndicator { UNDERLINE, RING, SUNSHINE, GLASS, CIRCLE }
    public static ActiveIndicator active_indicator = ActiveIndicator.UNDERLINE;

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
        var vals = parse(LumenCommon.Paths.panel_json());

        at_top            = vals.get_string_member_with_default("position", "") == "top";
        open_indicator    = parse_indicator(vals.get_string_member_with_default("app.open-indicator", ""));
        active_indicator  = parse_active_indicator(vals.get_string_member_with_default("app.active-indicator", ""));
        multi_monitor     = vals.get_boolean_member_with_default("behavior.multi-monitor", false);
        per_monitor_apps  = vals.get_boolean_member_with_default("behavior.per-monitor-apps", false);
        tray_all_monitors = vals.get_boolean_member_with_default("behavior.tray-all-monitors", false);
        show_launcher     = vals.get_boolean_member_with_default("app.launcher-button", false);
        var fmt = vals.get_string_member_with_default("clock.format", "");
        if (fmt.strip() != "") clock_format = fmt;

        // Absent (null) and present-but-unrecognised mean different things here:
        // only an absent key falls back to the legacy auto-hide bool.
        behavior_mode      = vals.has_member("behavior.mode")
            ? vals.get_string_member_with_default("behavior.mode", "") : null;
        behavior_auto_hide = vals.get_boolean_member_with_default("behavior.auto-hide", false);

        tray_order    = get_string_array(vals, "tray.order");
        tray_disabled = get_string_array(vals, "tray.disabled");
        if (tray_order.length == 0) {
            string[] defaults = {};
            foreach (var info in LumenTray.CATALOG) defaults += info.id;
            tray_order = defaults;
        }
    }

    // Fail-soft: a missing or unparseable file yields an empty object.
    static Json.Object parse (string path) {
        if (!FileUtils.test(path, FileTest.EXISTS)) return new Json.Object();
        var parser = new Json.Parser();
        try {
            parser.load_from_file(path);
        } catch (Error e) {
            stderr.printf("PanelConfig: load %s failed: %s\n", path, e.message);
            return new Json.Object();
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return new Json.Object();
        return root.get_object();
    }

    // String-array getter: strips, drops empties. Non-array/missing ⇒ empty.
    static string[] get_string_array (Json.Object o, string key) {
        string[] result = {};
        if (!o.has_member(key)) return result;
        var n = o.get_member(key);
        if (n.get_node_type() != Json.NodeType.ARRAY) return result;
        foreach (var elem in n.get_array().get_elements()) {
            if (elem.get_node_type() != Json.NodeType.VALUE) continue;
            if (elem.get_value_type() != typeof(string)) continue;
            var s = elem.get_string().strip();
            if (s != "") result += s;
        }
        return result;
    }

    // tray_order plus any catalog ids it lacks (so new applets appear after an
    // upgrade), minus disabled and unknown ids.
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
            case "round":   return OpenIndicator.ROUND;
            case "none":    return OpenIndicator.NONE;
            default:        return OpenIndicator.SHADE;
        }
    }

    static ActiveIndicator parse_active_indicator (string? s) {
        switch (s) {
            case "ring":      return ActiveIndicator.RING;
            case "sunshine":  return ActiveIndicator.SUNSHINE;
            case "glass":     return ActiveIndicator.GLASS;
            case "circle":    return ActiveIndicator.CIRCLE;
            case "underline": return ActiveIndicator.UNDERLINE;
            default:          return ActiveIndicator.UNDERLINE;
        }
    }
}
