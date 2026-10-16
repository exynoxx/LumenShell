using GLib;

public class BtDevice : GLib.Object {
    public string mac;        // AA:BB:CC:DD:EE:FF
    public string name;       // friendly name (falls back to mac)
    public string dev_icon;   // bluez "Icon" property — audio-card, input-mouse, phone, …
    public bool   paired;
    public bool   connected;

    public BtDevice(string mac, string name, string dev_icon, bool paired, bool connected) {
        this.mac       = mac;
        this.name      = name;
        this.dev_icon  = dev_icon;
        this.paired    = paired;
        this.connected = connected;
    }
}

public class BtDeviceDetails : GLib.Object {
    public string mac          = "";
    public string name         = "";
    public string dev_icon     = "";
    public bool   paired       = false;
    public bool   bonded       = false;
    public bool   trusted      = false;
    public bool   connected    = false;
    public int    battery      = -1;   // -1 when absent
}

// Reads over BlueZ DBus; writes shell bluetoothctl, because pairing over DBus
// needs an org.bluez.Agent1 registration to answer passkey prompts.
public class BtctlClient : GLib.Object {

    public signal void changed();

    const string BLUEZ         = "org.bluez";
    const string OBJMGR_IFACE  = "org.freedesktop.DBus.ObjectManager";
    const string PROPS_IFACE   = "org.freedesktop.DBus.Properties";
    const string ADAPTER_IFACE = "org.bluez.Adapter1";
    const string DEVICE_IFACE  = "org.bluez.Device1";
    const string BATTERY_IFACE = "org.bluez.Battery1";

    DBusProxy? objmgr = null;

    public BtctlClient() {
        try {
            objmgr = new DBusProxy.for_bus_sync(
                BusType.SYSTEM, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES, null,
                BLUEZ, "/", OBJMGR_IFACE, null);
        } catch (Error e) {
            warning("btctl: cannot reach BlueZ ObjectManager: %s", e.message);
            return;
        }

        objmgr.g_signal.connect((sender, signal_name, parameters) => {
            if (signal_name == "InterfacesAdded" || signal_name == "InterfacesRemoved")
                changed();
        });

        var conn = objmgr.get_connection();
        foreach (var iface in new string[]{ ADAPTER_IFACE, DEVICE_IFACE, BATTERY_IFACE }) {
            conn.signal_subscribe(BLUEZ, PROPS_IFACE, "PropertiesChanged", null, iface,
                                  DBusSignalFlags.NONE,
                                  (c, s, path, i, sig, parameters) => { changed(); });
        }
    }

    // ---- reads (DBus) -------------------------------------------------------

    // path -> interface -> properties, for every object BlueZ exposes.
    Variant? managed_objects() {
        if (objmgr == null) return null;
        try {
            var reply = objmgr.call_sync("GetManagedObjects", null,
                                         DBusCallFlags.NONE, 3000, null);
            return reply.get_child_value(0);
        } catch (Error e) {
            return null;
        }
    }

    static string str_prop(Variant props, string key) {
        var v = props.lookup_value(key, VariantType.STRING);
        return v == null ? "" : v.get_string();
    }

    static bool bool_prop(Variant props, string key) {
        var v = props.lookup_value(key, VariantType.BOOLEAN);
        return v != null && v.get_boolean();
    }

    // `ifaces` is one object's a{sa{sv}}; null when it isn't a device.
    static BtDeviceDetails? parse_device(Variant ifaces) {
        var props = ifaces.lookup_value(DEVICE_IFACE, new VariantType("a{sv}"));
        if (props == null) return null;

        var d = new BtDeviceDetails();
        d.mac          = str_prop(props, "Address");
        d.name         = str_prop(props, "Name");
        d.dev_icon     = str_prop(props, "Icon");
        d.paired       = bool_prop(props, "Paired");
        d.bonded       = bool_prop(props, "Bonded");
        d.trusted      = bool_prop(props, "Trusted");
        d.connected    = bool_prop(props, "Connected");

        // Battery level lives on a sibling interface of the same object.
        var batt = ifaces.lookup_value(BATTERY_IFACE, new VariantType("a{sv}"));
        if (batt != null) {
            var pct = batt.lookup_value("Percentage", VariantType.BYTE);
            if (pct != null) d.battery = pct.get_byte();
        }

        if (d.name == "") d.name = d.mac;
        return d;
    }

    public bool query_powered() {
        var objects = managed_objects();
        if (objects == null) return false;

        for (size_t i = 0; i < objects.n_children(); i++) {
            var ifaces = objects.get_child_value(i).get_child_value(1);
            var props  = ifaces.lookup_value(ADAPTER_IFACE, new VariantType("a{sv}"));
            if (props != null) return bool_prop(props, "Powered");
        }
        return false;
    }

    public BtDevice[] fetch_devices() {
        BtDevice[] result = {};
        var objects = managed_objects();
        if (objects == null) return result;

        for (size_t i = 0; i < objects.n_children(); i++) {
            var d = parse_device(objects.get_child_value(i).get_child_value(1));
            if (d != null)
                result += new BtDevice(d.mac, d.name, d.dev_icon, d.paired, d.connected);
        }
        return result;
    }

    public BtDevice info(string mac) {
        var d = device_details(mac);
        return new BtDevice(d.mac, d.name, d.dev_icon, d.paired, d.connected);
    }

    public BtDeviceDetails device_details(string mac) {
        var objects = managed_objects();
        if (objects != null) {
            for (size_t i = 0; i < objects.n_children(); i++) {
                var d = parse_device(objects.get_child_value(i).get_child_value(1));
                if (d != null && d.mac.up() == mac.up()) return d;
            }
        }

        var missing = new BtDeviceDetails();
        missing.mac  = mac;
        missing.name = mac;
        return missing;
    }

    // ---- writes (bluetoothctl one-shot subcommands) -------------------------

    public void scan(uint secs) {
        LumenCommon.Proc.run_capture(new string[]{
            "bluetoothctl", "--timeout", "%u".printf(secs), "scan", "on"
        });
    }

    // Blocking. rfkill unblock first, otherwise `power on` fails with off-blocked.
    public void set_powered(bool on) {
        if (on) {
            LumenCommon.Proc.run_capture(new string[] { "rfkill", "unblock", "bluetooth" });
            LumenCommon.Proc.run_capture(new string[] { "bluetoothctl", "power", "on" });
        } else {
            LumenCommon.Proc.run_capture(new string[] { "bluetoothctl", "power", "off" });
        }
    }

    public void connect(string mac) {
        LumenCommon.Proc.spawn_detached(new string[] { "bluetoothctl", "connect", mac });
    }

    public void disconnect(string mac) {
        LumenCommon.Proc.spawn_detached(new string[] { "bluetoothctl", "disconnect", mac });
    }

    // Blocking. "Just works" pairing only; passkey/PIN confirmation is not handled.
    public void pair(string mac) {
        LumenCommon.Proc.run_capture(new string[] { "bluetoothctl", "pair",    mac });
        LumenCommon.Proc.run_capture(new string[] { "bluetoothctl", "trust",   mac });
        LumenCommon.Proc.run_capture(new string[] { "bluetoothctl", "connect", mac });
    }

    public void remove(string mac) {
        LumenCommon.Proc.spawn_detached(new string[] { "bluetoothctl", "remove", mac });
    }
}
