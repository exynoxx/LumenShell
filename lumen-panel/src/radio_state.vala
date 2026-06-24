using GLib;

// Remembered WiFi / Bluetooth power state, persisted across panel restarts and
// reboots. The tray toggles only ever mirror the live system state otherwise, so
// without this the radios come back in whatever the underlying daemons default to
// (notably BlueZ AutoEnable re-powers Bluetooth at boot). WifiService/BluetoothService
// write the user's choice here on toggle and re-apply it from their constructors.
//
// Stored as ~/.config/lumen-shell/radio-state.json with flat dotted bool keys
// ("wifi.enabled", "bluetooth.enabled"). An absent key reads as null — "never
// toggled" — so a fresh install applies nothing and the radios follow the system
// default; only an explicit saved value is enforced.
public class RadioState {

    static bool   loaded         = false;
    static bool?  wifi_enabled   = null;
    static bool?  bt_enabled     = null;

    static string path () {
        return Environment.get_user_config_dir() + "/lumen-shell/radio-state.json";
    }

    // Fail-soft parse, mirroring PanelConfig: a missing or unparseable file leaves
    // both values null, so every getter returns "unset".
    static void ensure_loaded () {
        if (loaded) return;
        loaded = true;

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
