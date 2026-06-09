using GLib;

/**
 * Outcome of a connection attempt — lets the UI distinguish a wrong
 * passphrase (worth re-prompting) from a generic failure.
 */
public enum WifiConnectResult {
    SUCCESS,
    BAD_PASSWORD,
    FAILED
}

/**
 * WifiNet — a scanned network record.
 */
public class WifiNet : GLib.Object {
    public string ssid;
    public int    signal;
    public string security;
    public bool   is_saved;   // a NetworkManager profile already exists for this SSID

    public WifiNet(string ssid, int signal, string security, bool is_saved = false) {
        this.ssid     = ssid;
        this.signal   = signal;
        this.security = security;
        this.is_saved = is_saved;
    }

    /** True when the network advertises some form of encryption. */
    public bool is_secured() {
        return security != "" && security != "--";
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

    /**
     * Connect to an SSID, blocking until nmcli finishes so the caller can
     * report success/failure. With from_saved, brings up the existing profile
     * (`connection up`, no passphrase needed); otherwise associates via
     * `device wifi connect`, passing the passphrase when one was given (open
     * networks pass none). Call from a background thread — this can block for
     * several seconds while NetworkManager negotiates the association.
     */
    public WifiConnectResult connect(string ssid, string password, bool from_saved) {
        string[] argv;
        if (from_saved)
            argv = new string[] { "nmcli", "connection", "up", "id", ssid };
        else if (password == "")
            argv = new string[] { "nmcli", "device", "wifi", "connect", ssid };
        else
            argv = new string[] { "nmcli", "device", "wifi", "connect", ssid, "password", password };

        string std_out = "", std_err = "";
        int status = -1;
        try {
            Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH,
                null, out std_out, out std_err, out status);
        } catch (SpawnError e) {
            return WifiConnectResult.FAILED;
        }

        bool ok = false;
        try { ok = Process.check_wait_status(status); } catch (Error e) { ok = false; }
        if (ok) return WifiConnectResult.SUCCESS;

        // NetworkManager reports a rejected passphrase a few different ways
        // depending on version; treat any secrets/auth wording as bad password
        // so the UI can re-prompt instead of showing a dead-end failure.
        string err = (std_err + " " + std_out).down();
        if (err.contains("secrets were required")
            || err.contains("no secrets")
            || err.contains("802-11-wireless-security")
            || err.contains("802.1x")
            || err.contains("authentication")
            || err.contains("password"))
            return WifiConnectResult.BAD_PASSWORD;
        return WifiConnectResult.FAILED;
    }

    /**
     * SSIDs that already have a saved NetworkManager profile. These can be
     * re-joined without re-entering a passphrase, and NetworkManager will
     * auto-connect to them on its own at login / when in range.
     */
    public Gee.HashSet<string> saved_ssids() {
        var saved = new Gee.HashSet<string>();
        string out_str = "";
        try {
            Process.spawn_command_line_sync(
                "nmcli -t -f NAME,TYPE connection show",
                out out_str, null, null);
        } catch (SpawnError e) { return saved; }

        foreach (var line in out_str.split("\n")) {
            var p = split_terse(line, 2);
            if (p.length >= 2 && p[1] == "802-11-wireless" && p[0].strip() != "")
                saved.add(p[0].strip());
        }
        return saved;
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

        var saved = saved_ssids();
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
            result += new WifiNet(ssid, signal, p[2], saved.contains(ssid));
        }
        return result;
    }
}
