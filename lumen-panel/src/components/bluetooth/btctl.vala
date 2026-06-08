using GLib;

/**
 * BtDevice — a known or discovered Bluetooth device.
 */
public class BtDevice : GLib.Object {
    public string mac;        // AA:BB:CC:DD:EE:FF
    public string name;       // friendly name (falls back to mac)
    public string dev_icon;   // bluez "Icon:" field — audio-card, input-mouse, phone, …
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

/**
 * BtctlClient — all bluetoothctl shelling in one place.
 *
 * bluetoothctl accepts one-shot subcommands non-interactively, so reads use
 * Process.spawn_command_line_sync (blocking) and fire-and-forget actions use
 * Utils.spawn_argv — the same split NmcliClient uses for nmcli.
 *
 * Shared by BluetoothTray (icon state) and BluetoothPage (device list).
 */
public class BtctlClient : GLib.Object {

    /** Value after the first ':' on a tab-indented "Key: value" info line. */
    private string field_value(string line) {
        int idx = line.index_of_char(':');
        if (idx < 0) return "";
        return line.substring(idx + 1).strip();
    }

    /** True if the controller is powered on. False if powered off or absent. */
    public bool query_powered() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync("bluetoothctl show", out out_str, null, null);
        } catch (SpawnError e) { return false; }

        foreach (var line in out_str.split("\n")) {
            var t = line.strip();
            if (t.has_prefix("Powered:")) return field_value(t) == "yes";
        }
        return false;
    }

    /**
     * Return the known device set, each enriched via `bluetoothctl info`.
     * De-duplicated by MAC. `discovered_only_paired` skips the info probe and
     * marks everything paired — used as a cheap fallback when power is off.
     */
    public BtDevice[] fetch_devices() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync("bluetoothctl devices", out out_str, null, null);
        } catch (SpawnError e) { return {}; }

        BtDevice[] result = {};
        var seen = new GLib.HashTable<string, bool>(str_hash, str_equal);

        foreach (var line in out_str.split("\n")) {
            // "Device AA:BB:CC:DD:EE:FF Friendly Name"
            var t = line.strip();
            if (!t.has_prefix("Device ")) continue;
            string rest = t.substring(7).strip();
            int sp = rest.index_of_char(' ');
            string mac  = sp < 0 ? rest : rest.substring(0, sp);
            if (mac == "" || seen.contains(mac)) continue;
            seen.insert(mac, true);
            result += info(mac);
        }
        return result;
    }

    /** Full detail for one device via `bluetoothctl info <mac>`. */
    public BtDevice info(string mac) {
        string out_str = "";
        try {
            Process.spawn_command_line_sync("bluetoothctl info " + mac, out out_str, null, null);
        } catch (SpawnError e) {
            return new BtDevice(mac, mac, "", false, false);
        }

        string name      = mac;
        string dev_icon  = "";
        bool   paired    = false;
        bool   connected = false;

        foreach (var line in out_str.split("\n")) {
            var t = line.strip();
            if      (t.has_prefix("Name:"))      name      = field_value(t);
            else if (t.has_prefix("Icon:"))      dev_icon  = field_value(t);
            else if (t.has_prefix("Paired:"))    paired    = field_value(t) == "yes";
            else if (t.has_prefix("Connected:")) connected = field_value(t) == "yes";
        }
        if (name == "") name = mac;
        return new BtDevice(mac, name, dev_icon, paired, connected);
    }

    /** Block for `secs` while bluetoothctl discovers nearby devices. */
    public void scan(uint secs) {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "bluetoothctl --timeout %u scan on".printf(secs),
                out out_str, null, null);
        } catch (SpawnError e) {}
    }

    /**
     * Power the controller on or off. Powering on first clears any rfkill
     * soft-block, otherwise `bluetoothctl power on` fails with off-blocked.
     * Blocking sequence — call from a background thread.
     */
    public void set_powered(bool on) {
        if (on) {
            run_sync(new string[] { "rfkill", "unblock", "bluetooth" });
            run_sync(new string[] { "bluetoothctl", "power", "on" });
        } else {
            run_sync(new string[] { "bluetoothctl", "power", "off" });
        }
    }

    public void connect(string mac) {
        Utils.spawn_argv(new string[] { "bluetoothctl", "connect", mac });
    }

    public void disconnect(string mac) {
        Utils.spawn_argv(new string[] { "bluetoothctl", "disconnect", mac });
    }

    /**
     * Pair → trust → connect, run synchronously in order. Best-effort
     * "just works" pairing; interactive passkey/PIN confirmation is not
     * handled. Call from a background thread — each step blocks.
     */
    public void pair(string mac) {
        run_sync(new string[] { "bluetoothctl", "pair",    mac });
        run_sync(new string[] { "bluetoothctl", "trust",   mac });
        run_sync(new string[] { "bluetoothctl", "connect", mac });
    }

    /** Unpair / forget a device. */
    public void remove(string mac) {
        Utils.spawn_argv(new string[] { "bluetoothctl", "remove", mac });
    }

    private void run_sync(string[] argv) {
        try {
            Process.spawn_sync(null, argv, null,
                SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL
                    | SpawnFlags.STDERR_TO_DEV_NULL,
                null, null, null, null);
        } catch (SpawnError e) {}
    }
}
