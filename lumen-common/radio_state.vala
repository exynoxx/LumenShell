using GLib;

// Remembered radio power state. An absent key reads as null ("never toggled"),
// so a fresh install enforces nothing and follows the system default.
public class RadioState {

    static bool?  wifi_enabled   = null;
    static bool?  bt_enabled     = null;

    static string path () {
        return LumenCommon.Paths.radio_state_json();
    }

    // Re-read every call (cheap, rare): lumen-settings writes the same file from
    // another process, so a cached copy would re-apply a stale state on resume.
    // Fail-soft: a missing or unparseable file leaves both values null.
    static void ensure_loaded () {
        wifi_enabled = null;
        bt_enabled   = null;

        var p = path();
        if (!FileUtils.test(p, FileTest.EXISTS)) return;
        var parser = new Json.Parser();
        try {
            parser.load_from_file(p);
        } catch (Error e) {
            stderr.printf("RadioState: load %s failed: %s\n", p, e.message);
            return;
        }
        var root = parser.get_root();
        if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return;
        var obj = root.get_object();
        wifi_enabled = read_bool(obj, "wifi.enabled");
        bt_enabled   = read_bool(obj, "bluetooth.enabled");
    }

    static bool? read_bool (Json.Object obj, string key) {
        if (!obj.has_member(key)) return null;
        var n = obj.get_member(key);
        if (n.get_node_type() != Json.NodeType.VALUE) return null;
        if (n.get_value_type() != typeof(bool)) return null;
        return n.get_boolean();
    }

    static void save () {
        var obj = new Json.Object();
        if (wifi_enabled != null) obj.set_boolean_member("wifi.enabled", wifi_enabled);
        if (bt_enabled   != null) obj.set_boolean_member("bluetooth.enabled", bt_enabled);

        var root = new Json.Node(Json.NodeType.OBJECT);
        root.set_object(obj);
        var gen = new Json.Generator();
        gen.set_root(root);
        gen.pretty = true;

        var p = path();
        try {
            DirUtils.create_with_parents(Path.get_dirname(p), 0755);
            FileUtils.set_contents(p, gen.to_data(null));
        } catch (Error e) {
            stderr.printf("RadioState: write %s failed: %s\n", p, e.message);
        }
    }

    public static bool? get_wifi () {
        ensure_loaded();
        return wifi_enabled;
    }

    public static bool? get_bluetooth () {
        ensure_loaded();
        return bt_enabled;
    }

    public static void set_wifi (bool on) {
        ensure_loaded();
        wifi_enabled = on;
        save();
    }

    public static void set_bluetooth (bool on) {
        ensure_loaded();
        bt_enabled = on;
        save();
    }
}
