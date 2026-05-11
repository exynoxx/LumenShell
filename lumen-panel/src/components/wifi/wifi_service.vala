using GLib;

/**
 * WifiService — single nmcli ownership shared by WifiTray and WifiPage.
 *
 * Drives one periodic poll of the connected SSID in a background thread,
 * plus on-demand network scans. state_changed fires on the main thread
 * after each result is applied.
 */
public class WifiService : GLib.Object {

    public signal void state_changed();

    public string    connected_ssid { get; private set; default = ""; }
    public WifiNet[] nets           = {};
    public bool      scanning       { get; private set; default = false; }

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

    /** Connect to an SSID. If password is "", uses an existing saved connection. */
    public void connect_to(string ssid, string password) {
        string[] argv = (password == "")
            ? new string[] { "nmcli", "connection", "up", "id", ssid }
            : new string[] { "nmcli", "device", "wifi", "connect", ssid, "password", password };
        spawn_argv(argv);
        schedule_rescan(1400);
    }

    /** Disconnect the wifi device, if any. */
    public void disconnect_active() {
        string dev = nmcli.get_wifi_device();
        if (dev == "") return;
        spawn_argv(new string[] { "nmcli", "device", "disconnect", dev });
        schedule_rescan(1000);
    }

    /** Full network scan + connection refresh. rescan=true asks nmcli to re-probe. */
    public void refresh_scan(bool rescan = false) {
        if (scan_in_flight) return;
        scan_in_flight = true;
        scanning       = true;
        state_changed();

        new GLib.Thread<void>("wifi-scan", () => {
            if (rescan)
                spawn_argv(new string[] { "nmcli", "device", "wifi", "rescan" });
            var new_nets = nmcli.fetch_nets();
            var new_conn = nmcli.query_connected();
            GLib.Idle.add(() => {
                nets           = new_nets;
                connected_ssid = new_conn;
                scanning       = false;
                scan_in_flight = false;
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

    // argv form avoids shell quoting entirely — SSID/password bytes pass
    // through unchanged and can never be reinterpreted by /bin/sh.
    private static void spawn_argv(string[] argv) {
        try {
            Pid pid;
            Process.spawn_async(null, argv, null, SpawnFlags.SEARCH_PATH, null, out pid);
            Process.close_pid(pid);
        } catch (SpawnError e) {}
    }

    private void poll_connection() {
        if (poll_in_flight) return;
        poll_in_flight = true;
        new GLib.Thread<void>("wifi-poll", () => {
            var conn = nmcli.query_connected();
            GLib.Idle.add(() => {
                poll_in_flight = false;
                if (conn != connected_ssid) {
                    connected_ssid = conn;
                    state_changed();
                }
                return Source.REMOVE;
            });
        });
    }
}
