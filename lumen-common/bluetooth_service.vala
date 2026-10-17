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

    public BluetoothService() {
        // Re-apply the remembered power state (beats BlueZ AutoEnable at boot).
        // Null ⇒ never toggled.
        var saved = RadioState.get_bluetooth();
        if (saved != null) apply_power(saved);
        else               poll_state();
        watch_bluez();
    }

    // Does NOT re-apply the saved power state, so merely constructing it (e.g. the
    // settings page) never toggles the user's Bluetooth.
    public BluetoothService.passive() {
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

    public void set_power(bool on) {
        RadioState.set_bluetooth(on);
        apply_power(on);
    }

    // Optimistic first so the toggle doesn't bounce back during the blocking call.
    private void apply_power(bool on) {
        powered = on;
        state_changed();
        new GLib.Thread<void>("bt-power", () => {
            btctl.set_powered(on);
            GLib.Idle.add(() => {
                // Powering on also runs a discovery scan.
                refresh_scan(on);
                return Source.REMOVE;
            });
        });
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
        new GLib.Thread<void>("bt-pair", () => {
            btctl.pair(mac);
            GLib.Idle.add(() => {
                refresh_scan(false);
                return Source.REMOVE;
            });
        });
    }

    public void remove_device(string mac) {
        btctl.remove(mac);
        schedule_rescan(800);
    }

    public void request_device_details(string mac) {
        new GLib.Thread<void>("bt-details", () => {
            var d = btctl.device_details(mac);
            GLib.Idle.add(() => {
                device_details_ready(d);
                return Source.REMOVE;
            });
        });
    }

    public void refresh_scan(bool rescan = false) {
        if (scan_in_flight) return;
        scan_in_flight = true;
        scanning       = true;
        state_changed();

        new GLib.Thread<void>("bt-scan", () => {
            if (rescan) btctl.scan(SCAN_SECS);
            var new_powered = btctl.query_powered();
            var new_devs    = btctl.fetch_devices();
            GLib.Idle.add(() => {
                powered        = new_powered;
                devices        = new_devs;
                connected_name = first_connected(new_devs);
                scanning       = false;
                scan_in_flight = false;
                state_changed();
                return Source.REMOVE;
            });
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
        new GLib.Thread<void>("bt-poll", () => {
            var pw   = btctl.query_powered();
            var devs = btctl.fetch_devices();
            var conn = first_connected(devs);
            var sig  = signature(devs);
            GLib.Idle.add(() => {
                poll_in_flight = false;
                bool changed = false;
                if (pw   != powered)        { powered = pw;          changed = true; }
                if (conn != connected_name) { connected_name = conn; changed = true; }
                // Battery and discovery updates arrive without a power/connection change.
                if (sig  != devices_sig)    { devices_sig = sig;     changed = true; }
                devices = devs;
                if (changed) state_changed();
                return Source.REMOVE;
            });
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
