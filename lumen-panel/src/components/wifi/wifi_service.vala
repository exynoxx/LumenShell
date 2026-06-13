using GLib;

public class WifiService : GLib.Object {

    public signal void state_changed();

    /** Fires on the main thread once a connect_to() attempt resolves. */
    public signal void connect_result(string ssid, WifiConnectResult result);

    public string    connected_ssid     { get; private set; default = ""; }
    public string    connecting_ssid    { get; private set; default = ""; }
    public WifiNet[] nets               = {};
    public bool      scanning           { get; private set; default = false; }
    public bool      enabled            { get; private set; default = true; }
    public bool      ethernet_connected { get; private set; default = false; }

    public bool connected { get { return connected_ssid != ""; } }

    private const uint POLL_INTERVAL_SEC = 4;

    private NmcliClient nmcli          = new NmcliClient();
    private bool        poll_in_flight = false;
    private bool        scan_in_flight = false;

    public WifiService() {
        poll_connection();
        GLib.Timeout.add_seconds(POLL_INTERVAL_SEC, () => {
            poll_connection();
            return Source.CONTINUE;
        });
    }

    public void set_radio(bool on) {
        // Optimistic: reflect the intent immediately so the toggle doesn't
        // bounce back while the (blocking) rfkill+nmcli sequence runs.
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

    /**
     * Connect to an SSID. If password is "", brings up an existing saved
     * connection. The attempt runs on a background thread; connect_result
     * fires with the outcome and the connection state is refreshed on success.
     */
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

    /** Full network scan + connection refresh. rescan=true asks nmcli to re-probe. */
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
            GLib.Idle.add(() => {
                enabled            = new_enabled;
                nets               = new_nets;
                connected_ssid     = new_conn;
                ethernet_connected = new_eth;
                scanning           = false;
                scan_in_flight     = false;
                state_changed();
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
