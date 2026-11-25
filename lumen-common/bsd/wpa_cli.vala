using GLib;

// FreeBSD-only: the NmcliClient API on the base system's own stack —
// wpa_supplicant(8) via wpa_cli(8) for Wi-Fi, ifconfig(8)/route(8) for
// addresses, and rc(8)'s netif service for wired links. WifiService picks this
// class instead of NmcliClient when built with --define=FREEBSD.
//
// wpa_cli talks to /var/run/wpa_supplicant/<if>, so wpa_supplicant.conf must
// carry `ctrl_interface_group=wheel` (or another group the user is in) and
// `update_config=1` for networks added here to persist. See
// scripts/freebsd/setup-system.sh.
public class WpaClient : GLib.Object {

    private GLib.Mutex lock_m = GLib.Mutex();
    private string?    wifi_if_cache = null;
    private string?    eth_if_cache  = null;
    private int64      if_cache_us   = 0;
    private const int64 IF_TTL_US = 5000000;

    // Cards attach/detach (USB, `service netif`), so re-list every few seconds.
    public void invalidate_devices() {
        lock_m.lock();
        if_cache_us = 0;
        lock_m.unlock();
    }

    private void refresh_ifaces() {
        lock_m.lock();
        bool fresh = GLib.get_monotonic_time() - if_cache_us < IF_TTL_US;
        lock_m.unlock();
        if (fresh) return;

        // wlan(4) clones form the `wlan` interface group.
        string wifi = "";
        var wl = (run({ "ifconfig", "-g", "wlan" }) ?? "").strip().split_set(" \n");
        var wlan_set = new GenericSet<string>(str_hash, str_equal);
        foreach (var w in wl) if (w != "") { wlan_set.add(w); if (wifi == "") wifi = w; }

        // Physical Ethernet: interfaces with a MAC that aren't Wi-Fi or
        // software (bridge, tap, epair, lagg members are still listed).
        string eth = "";
        var all = (run({ "ifconfig", "-l", "ether" }) ?? "").strip().split(" ");
        foreach (var i in all) {
            if (i == "" || wlan_set.contains(i)) continue;
            if (i.has_prefix("bridge") || i.has_prefix("tap") || i.has_prefix("epair")
                || i.has_prefix("vm-") || i.has_prefix("tun") || i.has_prefix("vlan"))
                continue;
            eth = i;
            break;
        }

        lock_m.lock();
        wifi_if_cache = wifi;
        eth_if_cache  = eth;
        if_cache_us   = GLib.get_monotonic_time();
        lock_m.unlock();
    }

    public string get_wifi_device() {
        refresh_ifaces();
        lock_m.lock();
        var r = wifi_if_cache ?? "";
        lock_m.unlock();
        return r;
    }

    public string get_ethernet_device() {
        refresh_ifaces();
        lock_m.lock();
        var r = eth_if_cache ?? "";
        lock_m.unlock();
        return r;
    }

    // ---- wpa_cli ---------------------------------------------------------

    private string? wpa(string[] args) {
        var dev = get_wifi_device();
        if (dev == "") return null;
        string[] argv = { "wpa_cli", "-i", dev };
        foreach (var a in args) argv += a;
        return run(argv);
    }

    private HashTable<string, string> status() {
        var t = new HashTable<string, string>(str_hash, str_equal);
        foreach (var line in (wpa({ "status" }) ?? "").split("\n")) {
            int eq = line.index_of_char('=');
            if (eq > 0) t.set(line.substring(0, eq), line.substring(eq + 1).strip());
        }
        return t;
    }

    private class Saved : GLib.Object {
        public string id;
        public string ssid;
        public string flags;
    }

    // `list_networks`: "network id / ssid / bssid / flags", tab-separated.
    private Saved[] saved_networks() {
        Saved[] list = {};
        var lines = (wpa({ "list_networks" }) ?? "").split("\n");
        foreach (var line in lines) {
            var p = line.split("\t");
            if (p.length < 4 || !p[0].strip().get_char(0).isdigit()) continue;
            var s = new Saved();
            s.id = p[0].strip(); s.ssid = p[1]; s.flags = p[3];
            list += s;
        }
        return list;
    }

    private string? saved_id(string ssid) {
        foreach (var s in saved_networks()) if (s.ssid == ssid) return s.id;
        return null;
    }

    public string query_connected() {
        var st = status();
        if (st.get("wpa_state") != "COMPLETED") return "";
        return st.get("ssid") ?? "";
    }

    // "Off" is a supplicant-level disconnect (wpa_cli disconnect), which
    // holds until reconnect, or the interface being down.
    public bool query_enabled() {
        var dev = get_wifi_device();
        if (dev == "") return false;
        var ifc = run({ "ifconfig", dev }) ?? "";
        if (!ifc.contains("<UP")) return false;
        var state = status().get("wpa_state") ?? "";
        return state != "" && state != "DISCONNECTED" && state != "INTERFACE_DISABLED";
    }

    public void set_enabled(bool on) {
        wpa({ on ? "reconnect" : "disconnect" });
    }

    public void rescan() {
        wpa({ "scan" });
    }

    // Blocking.
    public bool query_ethernet_connected() {
        var dev = get_ethernet_device();
        if (dev == "") return false;
        var ifc = run({ "ifconfig", dev }) ?? "";
        return ifc.contains("status: active") && ifc.contains("\tinet ");
    }

    // Root-only: rc(8)'s netif service also restarts dhclient. polkit prompts.
    public void set_ethernet_enabled(bool on) {
        string dev = get_ethernet_device();
        if (dev == "") return;
        LumenCommon.Proc.spawn_detached({
            "pkexec", "/usr/sbin/service", "netif", on ? "start" : "stop", dev
        });
    }

    // ---- scan results ----------------------------------------------------

    // wpa_supplicant's bsd driver reports dBm on most cards and a raw
    // noise-relative RSSI (0.5 dB units) on others; map both to 0..100.
    private static int signal_percent(int level) {
        if (level < 0) return ((level + 100) * 2).clamp(0, 100);
        return (level * 100 / 80).clamp(0, 100);
    }

    // "[WPA2-PSK-CCMP][ESS]" → "WPA2", matching nmcli's SECURITY column.
    private static string security_of(string flags) {
        if (flags.contains("SAE") || flags.contains("WPA3")) return "WPA3";
        if (flags.contains("WPA2") || flags.contains("RSN")) return "WPA2";
        if (flags.contains("WPA-"))  return "WPA1";
        if (flags.contains("WEP"))   return "WEP";
        return "";
    }

    public WifiNet[] fetch_nets(bool rescan = false) {
        if (rescan) {
            wpa({ "scan" });
            Thread.usleep(2500000);   // results land asynchronously
        }
        var saved = saved_ssids();
        var best  = new HashTable<string, WifiNet>(str_hash, str_equal);
        string[] order = {};
        // "bssid / frequency / signal level / flags / ssid"
        foreach (var line in (wpa({ "scan_results" }) ?? "").split("\n")) {
            var p = line.split("\t");
            if (p.length < 5 || p[0].index_of_char(':') < 0) continue;
            string ssid = unescape(p[4]);
            if (ssid == "") continue;
            int level = 0;
            int.try_parse(p[2], out level);
            int pct = signal_percent(level);
            var prev = best.get(ssid);
            if (prev == null) order += ssid;
            if (prev == null || pct > prev.signal)
                best.set(ssid, new WifiNet(ssid, pct, security_of(p[3]), saved.contains(ssid)));
        }
        WifiNet[] result = {};
        foreach (var s in order) result += best.get(s);
        return result;
    }

    // wpa_supplicant prints non-printable SSID bytes as \xNN.
    private static string unescape(string s) {
        if (!s.contains("\\")) return s;
        var sb = new StringBuilder();
        for (int i = 0; i < s.length; i++) {
            if (s[i] == '\\' && i + 3 < s.length && s[i + 1] == 'x'
                && s[i + 2].isxdigit() && s[i + 3].isxdigit()) {
                sb.append_c((char) (s[i + 2].xdigit_value() * 16 + s[i + 3].xdigit_value()));
                i += 3;
                continue;
            }
            if (s[i] == '\\' && i + 1 < s.length) { i++; }
            sb.append_c(s[i]);
        }
        return sb.str;
    }

    public Gee.HashSet<string> saved_ssids() {
        var set = new Gee.HashSet<string>();
        foreach (var s in saved_networks()) if (s.ssid != "") set.add(s.ssid);
        return set;
    }

    // ---- connect / disconnect / forget -----------------------------------

    // SSIDs go over as hex so quotes, spaces and UTF-8 survive wpa_cli's
    // single-line command protocol.
    private static string hex(string s) {
        var sb = new StringBuilder();
        for (int i = 0; i < s.length; i++) sb.append_printf("%02x", (uint8) s[i]);
        return sb.str;
    }

    private bool ok(string? reply) {
        return reply != null && ((!) reply).strip() == "OK";
    }

    // Blocking for seconds while associating — worker thread only.
    public new WifiConnectResult connect(string ssid, string password, bool from_saved) {
        if (from_saved) {
            var id = saved_id(ssid);
            if (id != null) return select_and_wait((!) id, false, password != "");
        }
        return add_and_connect(ssid, password, false);
    }

    public WifiConnectResult connect_hidden(string ssid, string password) {
        return add_and_connect(ssid, password, true);
    }

    // Known limitation, as with nmcli: the PSK is an argv element of the
    // short-lived wpa_cli (visible to ps(1) unless
    // security.bsd.see_other_uids=0).
    private WifiConnectResult add_and_connect(string ssid, string password, bool hidden) {
        var existing = saved_id(ssid);
        if (existing != null) wpa({ "remove_network", (!) existing });

        var id = (wpa({ "add_network" }) ?? "").strip();
        int n = 0;
        if (!int.try_parse(id, out n)) return WifiConnectResult.FAILED;

        bool good = ok(wpa({ "set_network", id, "ssid", hex(ssid) }));
        if (password == "")
            good = good && ok(wpa({ "set_network", id, "key_mgmt", "NONE" }));
        else
            good = good && ok(wpa({ "set_network", id, "psk", "\"" + password + "\"" }));
        if (hidden) good = good && ok(wpa({ "set_network", id, "scan_ssid", "1" }));
        if (!good) {
            wpa({ "remove_network", id });
            // Most likely a passphrase outside wpa_supplicant's 8..63 chars.
            return password != "" ? WifiConnectResult.BAD_PASSWORD : WifiConnectResult.FAILED;
        }
        var res = select_and_wait(id, true, password != "");
        if (res != WifiConnectResult.SUCCESS) wpa({ "remove_network", id });
        else wpa({ "save_config" });
        return res;
    }

    // Wrong keys show up as the network going [TEMP-DISABLED].
    private WifiConnectResult select_and_wait(string id, bool fresh, bool secured) {
        if (!ok(wpa({ "select_network", id }))) return WifiConnectResult.FAILED;
        if (!fresh) wpa({ "reassociate" });
        for (int i = 0; i < 40; i++) {   // 20 s, NetworkManager's order of patience
            Thread.usleep(500000);
            var st = status();
            if (st.get("wpa_state") == "COMPLETED" && st.get("id") == id) {
                if (!fresh) wpa({ "save_config" });
                return WifiConnectResult.SUCCESS;
            }
            foreach (var s in saved_networks()) {
                if (s.id == id && s.flags.contains("TEMP-DISABLED"))
                    return secured ? WifiConnectResult.BAD_PASSWORD : WifiConnectResult.FAILED;
            }
        }
        return WifiConnectResult.FAILED;
    }

    // Like NetworkManager's device disconnect: stay off this network until
    // the user picks it again (select_network re-enables it).
    public new void disconnect() {
        var id = status().get("id");
        if (id != null && id != "") wpa({ "disable_network", (!) id });
        else wpa({ "disconnect" });
    }

    public void forget(string ssid) {
        var id = saved_id(ssid);
        if (id == null) return;
        wpa({ "remove_network", (!) id });
        wpa({ "save_config" });
    }

    // ---- details ---------------------------------------------------------

    public NetDetails device_details(string dev) {
        var d = new NetDetails();
        if (dev == "") return d;
        var ifc = run({ "ifconfig", dev }) ?? "";
        foreach (var raw in ifc.split("\n")) {
            var f = raw.strip().split(" ");
            if (f.length >= 2 && f[0] == "ether") d.mac = f[1];
            if (f.length >= 4 && f[0] == "inet" && d.ip4 == "")
                d.ip4 = f[1] + "/" + prefix_len(f[3]).to_string();
        }
        if (d.ip4 == "") return d;

        // `route -n get default`: "gateway: 192.168.1.1", "interface: wlan0".
        string gw = "", gw_if = "";
        foreach (var raw in (run({ "route", "-n", "get", "default" }) ?? "").split("\n")) {
            var l = raw.strip();
            if (l.has_prefix("gateway:"))   gw    = l.substring(8).strip();
            if (l.has_prefix("interface:")) gw_if = l.substring(10).strip();
        }
        if (gw_if == dev) d.gateway = gw;

        // resolv.conf(5) is system-wide, as resolvconf(8) maintains it.
        string resolv = "";
        try { FileUtils.get_contents("/etc/resolv.conf", out resolv); } catch (FileError e) {}
        string[] dns = {};
        foreach (var raw in resolv.split("\n")) {
            var f = raw.strip().split_set(" \t");
            if (f.length >= 2 && f[0] == "nameserver") dns += f[f.length - 1];
        }
        d.dns = dns;
        return d;
    }

    // ifconfig prints IPv4 netmasks as hex: 0xffffff00 → 24.
    private static int prefix_len(string mask) {
        uint64 v = 0;
        if (mask.has_prefix("0x")) v = uint64.parse(mask.substring(2), 16);
        int n = 0;
        for (int i = 0; i < 32; i++) if ((v & ((uint64) 1 << i)) != 0) n++;
        return n;
    }

    public void active_ap(out string security, out string band) {
        security = "";
        band     = "";
        var st = status();
        if (st.get("wpa_state") != "COMPLETED") return;
        var km = st.get("key_mgmt") ?? "";
        if (km.contains("SAE"))       security = "WPA3";
        else if (km.contains("WPA2")) security = "WPA2";
        else if (km.contains("WPA"))  security = "WPA1";
        else if (km == "NONE")        security = "";
        int mhz = 0;
        if (int.try_parse(st.get("freq") ?? "", out mhz) && mhz > 0) {
            if      (mhz < 3000) band = "2.4 GHz";
            else if (mhz < 5925) band = "5 GHz";
            else                 band = "6 GHz";
        }
    }

    // wpa_supplicant never hands PSKs back over its control socket, and
    // /etc/wpa_supplicant.conf is root-only.
    public string connection_psk(string name) {
        return "";
    }

    private static string? run(string[] argv) {
        return LumenCommon.Proc.run_capture(argv, { "LC_ALL=C" });
    }
}
