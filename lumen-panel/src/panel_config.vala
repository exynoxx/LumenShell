using GLib;

// Global panel placement, read once at startup from panel.json (flat dotted
// keys, written by lumen-settings). Widgets that must mirror their layout when
// the panel sits at the top of the screen (popover direction, tray growth, the
// backdrop strip's edge) consult PanelConfig.at_top rather than threading the
// flag through every constructor.
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

    // Raw auto-hide behavior, resolved into a PanelWindow.Mode there (the enum
    // lives with the window). behavior_mode is the explicit "normal|hidden|push"
    // string; behavior_auto_hide is the legacy bool fallback when it's absent.
    public static string? behavior_mode = null;
    public static bool behavior_auto_hide = false;

    // Tray applet layout, from the "tray.order"/"tray.disabled" JSON arrays
    // (written by lumen-settings). tray_order is the full ordered list of applet
    // ids; tray_disabled is the subset toggled off. Absent tray.order leaves
    // tray_order at the catalog default and tray_disabled empty — byte-for-byte
    // identical to the old hardcoded tray. tray_enabled_order() resolves the two
    // against the shared catalog into what make_tray() actually builds.
    public static string[] tray_order = {};
    public static string[] tray_disabled = {};

    public static void load () {
        var path = Environment.get_user_config_dir() + "/lumen-shell/panel.json";
        var vals = parse(path);

        at_top            = get_string(vals, "position") == "top";
        open_indicator    = parse_indicator(get_string(vals, "app.open-indicator"));
        multi_monitor     = get_bool(vals, "behavior.multi-monitor");
        per_monitor_apps  = get_bool(vals, "behavior.per-monitor-apps");
        tray_all_monitors = get_bool(vals, "behavior.tray-all-monitors");
        show_launcher     = get_bool(vals, "app.launcher-button");
        var fmt = get_string(vals, "clock.format");
        if (fmt != null && fmt.strip() != "") clock_format = fmt;

        behavior_mode      = get_string(vals, "behavior.mode");
        behavior_auto_hide = get_bool(vals, "behavior.auto-hide");

        tray_order    = get_string_array(vals, "tray.order");
        tray_disabled = get_string_array(vals, "tray.disabled");
        // No tray.order ⇒ fall back to the catalog's canonical order.
        if (tray_order.length == 0) {
            string[] defaults = {};
            foreach (var info in LumenTray.CATALOG) defaults += info.id;
            tray_order = defaults;
        }
    }

    // Parse panel.json into a flat key→node table. Fail-soft: a missing or
    // unparseable file yields an empty table, so every getter returns its
    // default (a missing key reads as its zero-value, same as before).
    static GLib.HashTable<string, Json.Node> parse (string path) {
        var table = new GLib.HashTable<string, Json.Node>(str_hash, str_equal);
        if (!FileUtils.test(path, FileTest.EXISTS)) return table;
        var parser = new Json.Parser();
        try {
            parser.load_from_file(path);
        } catch (Error e) {
            stderr.printf("PanelConfig: load %s failed: %s\n", path, e.message);
            return table;
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return table;
        root.get_object().foreach_member((obj, name, node) => {
            table.insert(name, node.copy());
        });
        return table;
    }

    static string? get_string (GLib.HashTable<string, Json.Node> t, string key) {
        var n = t.lookup(key);
        if (n == null || n.get_node_type() != Json.NodeType.VALUE) return null;
        if (n.get_value_type() != typeof(string)) return null;
        return n.get_string();
    }

    static bool get_bool (GLib.HashTable<string, Json.Node> t, string key) {
        var n = t.lookup(key);
        if (n == null || n.get_node_type() != Json.NodeType.VALUE) return false;
        if (n.get_value_type() != typeof(bool)) return false;
        return n.get_boolean();
    }

    // String-array getter: strips, drops empties. Non-array/missing ⇒ empty.
    static string[] get_string_array (GLib.HashTable<string, Json.Node> t, string key) {
        string[] result = {};
        var n = t.lookup(key);
        if (n == null || n.get_node_type() != Json.NodeType.ARRAY) return result;
        foreach (var elem in n.get_array().get_elements()) {
            if (elem.get_node_type() != Json.NodeType.VALUE) continue;
            if (elem.get_value_type() != typeof(string)) continue;
            var s = elem.get_string().strip();
            if (s != "") result += s;
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
