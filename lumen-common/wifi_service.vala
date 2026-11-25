using GLib;

public class WifiService : GLib.Object {

    public signal void state_changed();

    public signal void connect_result(string ssid, WifiConnectResult result);

    public signal void details_ready(NetDetails wifi, NetDetails eth);

    public string    connected_ssid     { get; private set; default = ""; }
    public string    connecting_ssid    { get; private set; default = ""; }
    public WifiNet[] nets               = {};
    public bool      scanning           { get; private set; default = false; }
    public bool      enabled            { get; private set; default = true; }
    public bool      ethernet_connected { get; private set; default = false; }
    public string    ethernet_device    { get; private set; default = ""; }

    public bool connected { get { return connected_ssid != ""; } }

    // Fallback poll, only while `nmcli monitor` isn't running.
    private const uint POLL_INTERVAL_SEC = 4;
    private const uint EVENT_DEBOUNCE_MS = 300;

    private LumenCommon.LineWatcher watcher = new LumenCommon.LineWatcher();
    private uint poll_timer  = 0;
    private uint event_timer = 0;

#if FREEBSD
    // wpa_supplicant + ifconfig; see lumen-common/bsd/wpa_cli.vala.
    private WpaClient   nmcli          = new WpaClient();
#else
    private NmcliClient nmcli          = new NmcliClient();
#endif
    private bool        poll_in_flight = false;
    private bool        poll_again     = false;
    private bool        scan_in_flight = false;

    // Skips the periodic poll and monitor-driven polls (not explicit calls) while
    // set; a monitor event seen meanwhile polls once on unpause.
    private bool _paused = false;
    private bool dirty   = false;
    public bool paused {
        get { return _paused; }
        set {
            _paused = value;
            if (!value && dirty) {
                dirty = false;
                nmcli.invalidate_devices();
                poll_connection();
            }
        }
    }

    // Radio state persists without us: NetworkManager keeps WirelessEnabled
    // in its own state file. (FreeBSD: wpa_supplicant.conf, via rc.conf.)
    public WifiService() {
        poll_connection();
        init_watch();
    }

    // Any `nmcli monitor` line triggers a poll; the text is never parsed.
    private void init_watch() {
        watcher.line.connect(() => {
            if (paused) { dirty = true; return; }
            if (event_timer != 0) GLib.Source.remove(event_timer);
            event_timer = GLib.Timeout.add(EVENT_DEBOUNCE_MS, () => {
                event_timer = 0;
                nmcli.invalidate_devices();
                poll_connection();
                return Source.REMOVE;
            });
        });
        watcher.ended.connect(() => {
            start_poll();
            GLib.Timeout.add_seconds(5, () => { start_watch(); return Source.REMOVE; });
        });
        start_watch();
    }

    // FreeBSD: the routing socket reports link up/down, (dis)association
    // and DHCP address changes; any line triggers the same debounced poll.
    private void start_watch() {
        if (watcher.running) return;
#if FREEBSD
        string[] monitor = { "route", "-n", "monitor" };
#else
        string[] monitor = { "nmcli", "monitor" };
#endif
        if (watcher.start(monitor)) {
            if (poll_timer != 0) { GLib.Source.remove(poll_timer); poll_timer = 0; }
            poll_connection();
        } else {
            start_poll();
        }
    }

    private void start_poll() {
        if (poll_timer != 0) return;
        poll_timer = GLib.Timeout.add_seconds(POLL_INTERVAL_SEC, () => {
            if (!paused) poll_connection();
            return Source.CONTINUE;
        });
    }

    // Optimistic first so the toggle doesn't bounce back during the blocking call.
    public void set_radio(bool on) {
        enabled = on;
        if (!on) { nets = {}; connected_ssid = ""; }
        state_changed();
        LumenCommon.Proc.off_main("wifi-power", () => nmcli.set_enabled(on), () => refresh_scan(false));
    }

    public void connect_to(string ssid, string password, bool from_saved = false) {
        if (connecting_ssid != "") return;   // one attempt at a time
        connecting_ssid = ssid;
        state_changed();

        var res = WifiConnectResult.FAILED;
        LumenCommon.Proc.off_main("wifi-connect", () => { res = nmcli.connect(ssid, password, from_saved); }, () => on_connected(ssid, res));
    }

    // Off-thread: the device lookup may spawn `nmcli device` on cache expiry.
    public void disconnect_active() {
        new GLib.Thread<void>("wifi-disconnect", () => { nmcli.disconnect(); });
        schedule_rescan(1000);
    }

    public void forget(string ssid) {
        nmcli.forget(ssid);
        schedule_rescan(800);
    }

    public void refresh_scan(bool rescan = false) {
        if (scan_in_flight) return;
        scan_in_flight = true;
        scanning       = true;
        state_changed();

        bool new_enabled = false, new_eth = false;
        WifiNet[] new_nets = {};
        string new_conn = "", new_ethdev = "";
        LumenCommon.Proc.off_main("wifi-scan", () => {
            new_enabled = nmcli.query_enabled();
            if (rescan && new_enabled) nmcli.rescan();
            if (new_enabled) new_nets = nmcli.fetch_nets(rescan);
            new_conn   = nmcli.query_connected();
            new_eth    = nmcli.query_ethernet_connected();
            new_ethdev = nmcli.get_ethernet_device();
        }, () => {
            enabled            = new_enabled;
            nets               = new_nets;
            connected_ssid     = new_conn;
            ethernet_connected = new_eth;
            ethernet_device    = new_ethdev;
            scanning           = false;
            scan_in_flight     = false;
            state_changed();
        });
    }

    public void set_ethernet(bool on) {
        new GLib.Thread<void>("eth-power", () => { nmcli.set_ethernet_enabled(on); });
        schedule_rescan(1000);
    }

    public void connect_to_hidden(string ssid, string password) {
        if (connecting_ssid != "") return;
        connecting_ssid = ssid;
        state_changed();

        var res = WifiConnectResult.FAILED;
        LumenCommon.Proc.off_main("wifi-connect-hidden", () => { res = nmcli.connect_hidden(ssid, password); }, () => on_connected(ssid, res));
    }

    private void on_connected(string ssid, WifiConnectResult res) {
        connecting_ssid = "";
        connect_result(ssid, res);
        if (res == WifiConnectResult.SUCCESS) refresh_scan(false);
        else                                  state_changed();
    }

    public void request_details() {
        string conn = connected_ssid;
        string eth_dev = ethernet_device;
        NetDetails? wifi_det = null, eth_det = null;
        LumenCommon.Proc.off_main("wifi-details", () => {
            wifi_det = nmcli.device_details(nmcli.get_wifi_device());
            eth_det  = nmcli.device_details(eth_dev);
            string sec, band;
            nmcli.active_ap(out sec, out band);
            wifi_det.security = sec;
            wifi_det.band     = band;
            wifi_det.password = nmcli.connection_psk(conn);
        }, () => details_ready(wifi_det, eth_det));
    }

    private void schedule_rescan(uint delay_ms) {
        GLib.Timeout.add(delay_ms, () => {
            refresh_scan(true);
            return Source.REMOVE;
        });
    }

    // Calls made mid-poll re-run once it finishes.
    private void poll_connection() {
        if (poll_in_flight) { poll_again = true; return; }
        poll_in_flight = true;
        bool en = false, eth = false;
        string conn = "";
        LumenCommon.Proc.off_main("wifi-poll", () => {
            en   = nmcli.query_enabled();
            conn = nmcli.query_connected();
            eth  = nmcli.query_ethernet_connected();
        }, () => {
            poll_in_flight = false;
            if (poll_again) { poll_again = false; poll_connection(); }
            bool changed = false;
            if (en   != enabled)            { enabled = en;             changed = true; }
            if (conn != connected_ssid)     { connected_ssid = conn;    changed = true; }
            if (eth  != ethernet_connected) { ethernet_connected = eth; changed = true; }
            if (changed) state_changed();
        });
    }
}
