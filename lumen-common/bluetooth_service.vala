using GLib;

public class BluetoothService : GLib.Object {

    public signal void state_changed();

    public signal void device_details_ready(BtDeviceDetails d);

    public bool       powered        { get; private set; default = false; }
    public bool       scanning       { get; private set; default = false; }
    public BtDevice[] devices        = {};
    public string     connected_name { get; private set; default = ""; }

    public bool connected { get { return connected_name != ""; } }

    private const uint SCAN_SECS    = 8;
    private const uint COALESCE_MS  = 300;

    private BtctlClient btctl           = new BtctlClient();
    private bool        poll_in_flight  = false;
    private bool        scan_in_flight  = false;
    private bool        refresh_pending = false;
    private string      devices_sig     = "";

    // Power state persists without us: off is an rfkill soft-block that
    // systemd-rfkill restores at boot, on is BlueZ AutoEnable.
    public BluetoothService() {
        poll_state();
        watch_bluez();
    }

    // No poll timer; a discovery scan reports devices one at a time, so coalesce.
    private void watch_bluez() {
        btctl.changed.connect(() => {
            if (refresh_pending) return;
            refresh_pending = true;
            GLib.Timeout.add(COALESCE_MS, () => {
                refresh_pending = false;
                poll_state();
                return Source.REMOVE;
            });
        });
    }

    // Optimistic first so the toggle doesn't bounce back during the blocking call.
    public void set_power(bool on) {
        powered = on;
        state_changed();
        // Powering on also runs a discovery scan.
        LumenCommon.Proc.off_main("bt-power", () => btctl.set_powered(on), () => refresh_scan(on));
    }

    public void connect_device(string mac) {
        btctl.connect(mac);
        schedule_rescan(1600);
    }

    public void disconnect_device(string mac) {
        btctl.disconnect(mac);
        schedule_rescan(1000);
    }

    public void pair_device(string mac) {
        LumenCommon.Proc.off_main("bt-pair", () => btctl.pair(mac), () => refresh_scan(false));
    }

    public void remove_device(string mac) {
        btctl.remove(mac);
        schedule_rescan(800);
    }

    public void request_device_details(string mac) {
        BtDeviceDetails? d = null;
        LumenCommon.Proc.off_main("bt-details", () => { d = btctl.device_details(mac); }, () => device_details_ready(d));
    }

    public void refresh_scan(bool rescan = false) {
        if (scan_in_flight) return;
        scan_in_flight = true;
        scanning       = true;
        state_changed();

        bool new_powered = false;
        BtDevice[] new_devs = {};
        LumenCommon.Proc.off_main("bt-scan", () => {
            if (rescan) btctl.scan(SCAN_SECS);
            new_devs = btctl.fetch_state(out new_powered);
        }, () => {
            powered        = new_powered;
            devices        = new_devs;
            connected_name = first_connected(new_devs);
            scanning       = false;
            scan_in_flight = false;
            state_changed();
        });
    }

    private void schedule_rescan(uint delay_ms) {
        GLib.Timeout.add(delay_ms, () => {
            refresh_scan(false);
            return Source.REMOVE;
        });
    }

    private void poll_state() {
        if (poll_in_flight) return;
        poll_in_flight = true;
        bool pw = false;
        BtDevice[] devs = {};
        LumenCommon.Proc.off_main("bt-poll", () => { devs = btctl.fetch_state(out pw); }, () => {
            poll_in_flight = false;
            bool changed = false;
            var conn = first_connected(devs);
            var sig  = signature(devs);
            if (pw   != powered)        { powered = pw;          changed = true; }
            if (conn != connected_name) { connected_name = conn; changed = true; }
            // Battery and discovery updates arrive without a power/connection change.
            if (sig  != devices_sig)    { devices_sig = sig;     changed = true; }
            devices = devs;
            if (changed) state_changed();
        });
    }

    private static string signature(BtDevice[] devs) {
        var b = new StringBuilder();
        foreach (var d in devs)
            b.append_printf("%s\t%s\t%s\t%s\t%d|", d.mac, d.name, d.paired.to_string(),
                            d.connected.to_string(), d.battery);
        return b.str;
    }

    private static string first_connected(BtDevice[] devs) {
        foreach (var d in devs) if (d.connected) return d.name;
        return "";
    }
}
