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

    /** Ask nmcli to re-probe visible networks. Blocking. */
    public void rescan() {
        spawn_argv(new string[] { "nmcli", "device", "wifi", "rescan" });
    }

    /** Connect to an SSID. If password is "", uses an existing saved connection. */
    public void connect(string ssid, string password) {
        string[] argv = (password == "")
            ? new string[] { "nmcli", "connection", "up", "id", ssid }
            : new string[] { "nmcli", "device", "wifi", "connect", ssid, "password", password };
        spawn_argv(argv);
    }

    /** Disconnect the wifi device, if any. No-op when there is no wifi device. */
    public void disconnect() {
        string dev = get_wifi_device();
        if (dev == "") return;
        spawn_argv(new string[] { "nmcli", "device", "disconnect", dev });
    }

    // argv form avoids shell quoting entirely — SSID/password bytes pass
    // through unchanged and can never be reinterpreted by /bin/sh.
    private static void spawn_argv(string[] argv) {
        try {
            Pid pid;
            Process.spawn_async(null, argv, null, SpawnFlags.SEARCH_PATH, null, out pid);
            Process.close_pid(pid);
        } catch (SpawnError e) {}
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
