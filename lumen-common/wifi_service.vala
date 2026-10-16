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

    private const uint POLL_INTERVAL_SEC = 4;

    private NmcliClient nmcli          = new NmcliClient();
    private bool        poll_in_flight = false;
    private bool        scan_in_flight = false;

    public WifiService() {
        // Re-apply the remembered radio state; null ⇒ never toggled ⇒ just poll.
        var saved = RadioState.get_wifi();
        if (saved != null) apply_radio(saved);
        else               poll_connection();
        GLib.Timeout.add_seconds(POLL_INTERVAL_SEC, () => {
            poll_connection();
            return Source.CONTINUE;
        });
    }

    // Does NOT re-apply the saved radio state, so merely constructing it (e.g. the
    // settings page) never toggles the user's WiFi.
    public WifiService.passive() {
        poll_connection();
        GLib.Timeout.add_seconds(POLL_INTERVAL_SEC, () => {
            poll_connection();
            return Source.CONTINUE;
        });
    }

    public void set_radio(bool on) {
        RadioState.set_wifi(on);
        apply_radio(on);
    }

    // Optimistic first so the toggle doesn't bounce back during the blocking call.
    private void apply_radio(bool on) {
        enabled = on;
        if (!on) { nets = {}; connected_ssid = ""; }
        state_changed();
        new GLib.Thread<void>("wifi-power", () => {
            nmcli.set_enabled(on);
            GLib.Idle.add(() => {
                refresh_scan(false);
                return Source.REMOVE;
            });
        });
    }

    public void connect_to(string ssid, string password, bool from_saved = false) {
        if (connecting_ssid != "") return;   // one attempt at a time
        connecting_ssid = ssid;
        state_changed();

        new GLib.Thread<void>("wifi-connect", () => {
            var res = nmcli.connect(ssid, password, from_saved);
            GLib.Idle.add(() => {
                connecting_ssid = "";
                connect_result(ssid, res);
                if (res == WifiConnectResult.SUCCESS) refresh_scan(false);
                else                                  state_changed();
                return Source.REMOVE;
            });
        });
    }

    public void disconnect_active() {
        nmcli.disconnect();
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

        new GLib.Thread<void>("wifi-scan", () => {
            bool new_enabled = nmcli.query_enabled();
            if (rescan && new_enabled) nmcli.rescan();
            var new_nets = new_enabled ? nmcli.fetch_nets() : new WifiNet[0];
            var new_conn = nmcli.query_connected();
            var new_eth  = nmcli.query_ethernet_connected();
            var new_ethdev = nmcli.get_ethernet_device();
            GLib.Idle.add(() => {
                enabled            = new_enabled;
                nets               = new_nets;
                connected_ssid     = new_conn;
                ethernet_connected = new_eth;
                ethernet_device    = new_ethdev;
                scanning           = false;
                scan_in_flight     = false;
                state_changed();
                return Source.REMOVE;
            });
        });
    }

    public void set_ethernet(bool on) {
        nmcli.set_ethernet_enabled(on);
        schedule_rescan(1000);
    }

    public void connect_to_hidden(string ssid, string password) {
        if (connecting_ssid != "") return;
        connecting_ssid = ssid;
        state_changed();

        new GLib.Thread<void>("wifi-connect-hidden", () => {
            var res = nmcli.connect_hidden(ssid, password);
            GLib.Idle.add(() => {
                connecting_ssid = "";
                connect_result(ssid, res);
                if (res == WifiConnectResult.SUCCESS) refresh_scan(false);
                else                                  state_changed();
                return Source.REMOVE;
            });
        });
    }

    public void request_details() {
        string conn = connected_ssid;
        new GLib.Thread<void>("wifi-details", () => {
            var wifi_det = nmcli.device_details(nmcli.get_wifi_device());
            var eth_det  = nmcli.device_details(ethernet_device);

            string sec, band;
            nmcli.active_ap(out sec, out band);
            wifi_det.security = sec;
            wifi_det.band     = band;
            wifi_det.password = nmcli.connection_psk(conn);

            GLib.Idle.add(() => {
                details_ready(wifi_det, eth_det);
                return Source.REMOVE;
            });
        });
    }

    private void schedule_rescan(uint delay_ms) {
        GLib.Timeout.add(delay_ms, () => {
            refresh_scan(true);
            return Source.REMOVE;
        });
    }

    private void poll_connection() {
        if (poll_in_flight) return;
        poll_in_flight = true;
        new GLib.Thread<void>("wifi-poll", () => {
            var en   = nmcli.query_enabled();
            var conn = nmcli.query_connected();
            var eth  = nmcli.query_ethernet_connected();
            GLib.Idle.add(() => {
                poll_in_flight = false;
                bool changed = false;
                if (en   != enabled)            { enabled = en;             changed = true; }
                if (conn != connected_ssid)     { connected_ssid = conn;    changed = true; }
                if (eth  != ethernet_connected) { ethernet_connected = eth; changed = true; }
                if (changed) state_changed();
                return Source.REMOVE;
            });
        });
    }
}
