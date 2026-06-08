using GLib;

/**
 * WifiNet — a scanned network record.
 */
public class WifiNet : GLib.Object {
    public string ssid;
    public int    signal;
    public string security;

    public WifiNet(string ssid, int signal, string security) {
        this.ssid     = ssid;
        this.signal   = signal;
        this.security = security;
    }
}

/**
 * NmcliClient — all nmcli shelling in one place.
 *
 * Shared by WifiTray (for icon state) and WifiPage (for the full network list).
 */
public class NmcliClient : GLib.Object {

    /**
     * Split an nmcli terse-format line on ':' with backslash-escape support.
     * Stops splitting after max_fields fields (-1 = unlimited).
     */
    private string[] split_terse(string line, int max_fields = -1) {
        string[] parts = {};
        var sb = new GLib.StringBuilder();
        bool escaped = false;
        int split_count = 0;

        for (int i = 0; i < line.length; i++) {
            char c = line[i];

            if (escaped) {
                sb.append_c(c);
                escaped = false;
                continue;
            }

            if (c == '\\') {
                escaped = true;
                continue;
            }

            if (c == ':' && (max_fields < 0 || split_count < max_fields - 1)) {
                parts += sb.str;
                sb.truncate(0);
                split_count++;
                continue;
            }

            sb.append_c(c);
        }

        if (escaped) sb.append_c('\\');
        parts += sb.str;
        return parts;
    }

    /** Return the SSID of the currently connected WiFi network, or "". */
    public string query_connected() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device",
                out out_str, null, null);
        } catch (SpawnError e) { return ""; }

        foreach (var line in out_str.split("\n")) {
            var p = split_terse(line, 4);
            if (p.length >= 4 && p[1] == "wifi" && p[2] == "connected")
                return p[3];
        }
        return "";
    }

    /** True if any wired ethernet device is in the connected state. */
    public bool query_ethernet_connected() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE device",
                out out_str, null, null);
        } catch (SpawnError e) { return false; }

        foreach (var line in out_str.split("\n")) {
            var p = split_terse(line, 3);
            if (p.length >= 3 && p[1] == "ethernet" && p[2] == "connected")
                return true;
        }
        return false;
    }

    /** Return the name of the WiFi network interface, or "". */
    public string get_wifi_device() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f DEVICE,TYPE,STATE device",
                out out_str, null, null);
        } catch (SpawnError e) { return ""; }

        foreach (var line in out_str.split("\n")) {
            var p = split_terse(line, 3);
            if (p.length >= 3 && p[1] == "wifi")
                return p[0];
        }
        return "";
    }

    /** True if the WiFi radio is enabled (`nmcli radio wifi` → "enabled"). */
    public bool query_enabled() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync("nmcli radio wifi", out out_str, null, null);
        } catch (SpawnError e) { return false; }
        return out_str.strip() == "enabled";
    }

    /**
     * Enable or disable the WiFi radio. Blocking — call from a background
     * thread. rfkill unblock clears any hard/soft block first, mirroring the
     * bluetooth power path, otherwise `nmcli radio wifi on` can no-op.
     */
    public void set_enabled(bool on) {
        if (on) run_sync(new string[] { "rfkill", "unblock", "wifi" });
        run_sync(new string[] { "nmcli", "radio", "wifi", on ? "on" : "off" });
    }

    private void run_sync(string[] argv) {
        try {
            Process.spawn_sync(null, argv, null,
                SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL
                    | SpawnFlags.STDERR_TO_DEV_NULL,
                null, null, null, null);
        } catch (SpawnError e) {}
    }

    /** Ask nmcli to re-probe visible networks. Blocking. */
    public void rescan() {
        Utils.spawn_argv(new string[] { "nmcli", "device", "wifi", "rescan" });
    }

    /** Connect to an SSID. If password is "", uses an existing saved connection. */
    public void connect(string ssid, string password) {
        string[] argv = (password == "")
            ? new string[] { "nmcli", "connection", "up", "id", ssid }
            : new string[] { "nmcli", "device", "wifi", "connect", ssid, "password", password };
        Utils.spawn_argv(argv);
    }

    /** Disconnect the wifi device, if any. No-op when there is no wifi device. */
    public void disconnect() {
        string dev = get_wifi_device();
        if (dev == "") return;
        Utils.spawn_argv(new string[] { "nmcli", "device", "disconnect", dev });
    }

    /** Scan and return the list of visible networks (de-duplicated by SSID). */
    public WifiNet[] fetch_nets() {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list",
                out out_str, null, null);
        } catch (SpawnError e) { return {}; }

        WifiNet[] result = {};
        var seen = new GLib.HashTable<string, bool>(str_hash, str_equal);

        foreach (var line in out_str.split("\n")) {
            var p = split_terse(line, 3);
            if (p.length < 3) continue;
            string ssid = p[0].strip();
            if (ssid == "" || ssid == "--") continue;
            if (seen.contains(ssid)) continue;
            seen.insert(ssid, true);
            int signal = 0;
            if (!int.try_parse(p[1], out signal)) continue;
            result += new WifiNet(ssid, signal, p[2]);
        }
        return result;
    }
}
