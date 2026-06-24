using GLib;

public class BluetoothService : GLib.Object {

    public signal void state_changed();

    public bool       powered        { get; private set; default = false; }
    public bool       scanning       { get; private set; default = false; }
    public BtDevice[] devices        = {};
    public string     connected_name { get; private set; default = ""; }

    public bool connected { get { return connected_name != ""; } }

    private const uint POLL_INTERVAL_SEC = 4;
    private const uint SCAN_SECS         = 8;

    private BtctlClient btctl          = new BtctlClient();
    private bool        poll_in_flight = false;
    private bool        scan_in_flight = false;

    public BluetoothService() {
        // Re-apply the remembered power state before the first poll, so a panel
        // restart (or boot, where BlueZ AutoEnable would otherwise power the
        // adapter on) restores the user's last choice. Null ⇒ never toggled.
        var saved = RadioState.get_bluetooth();
        if (saved != null) apply_power(saved);
        else               poll_state();
        GLib.Timeout.add_seconds(POLL_INTERVAL_SEC, () => {
            poll_state();
            return Source.CONTINUE;
        });
    }

    public void set_power(bool on) {
        RadioState.set_bluetooth(on);
        apply_power(on);
    }

    // Push the adapter to `on` on a worker thread (rfkill+bluetoothctl block),
    // reflecting the intent optimistically first so the toggle doesn't bounce back.
    private void apply_power(bool on) {
        powered = on;
        state_changed();
        new GLib.Thread<void>("bt-power", () => {
            btctl.set_powered(on);
            GLib.Idle.add(() => {
                // Powering on: run a discovery scan so nearby devices appear
                // without the user having to hit "Scan" manually. Powering
                // off: just refresh the (now empty) list.
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
            GLib.Idle.add(() => {
                poll_in_flight = false;
                bool changed = false;
                if (pw   != powered)        { powered = pw;          changed = true; }
                if (conn != connected_name) { connected_name = conn; changed = true; }
                // Always adopt the freshest list so the page reflects newly
                // (un)paired devices even when power/connection are unchanged.
                devices = devs;
                if (changed) state_changed();
                return Source.REMOVE;
            });
        });
    }

    private static string first_connected(BtDevice[] devs) {
        foreach (var d in devs) if (d.connected) return d.name;
        return "";
    }
}
