using GLib;

/**
 * BatteryService — single sysfs read path shared by BatteryTray and BatteryPage.
 *
 * Call refresh() to update all fields; state_changed fires when done.
 */
public class BatteryService : GLib.Object {

    public signal void state_changed();

    public string raw_status  = "";
    public int    percent     = 0;
    public float  voltage_v   = 0f;
    public float  current_a   = 0f;
    public int    charge_full = 0;
    public int    charge_now  = 0;

    public void refresh() {
        raw_status  = sysfs_str("status").down().strip();
        charge_full = sysfs_int("charge_full");
        charge_now  = sysfs_int("charge_now");
        voltage_v   = sysfs_int("voltage_now") / 1000000f;
        current_a   = sysfs_int("current_now") / 1000000f;

        if (charge_full > 0)
            percent = (int)((charge_now / (float) charge_full) * 100);
        percent = int.min(100, int.max(0, percent));

        state_changed();
    }

    public static string sysfs_str(string name) {
        string out_str, err;
        try {
            int exit;
            Process.spawn_command_line_sync(
                "cat /sys/class/power_supply/BAT0/" + name,
                out out_str, out err, out exit);
            return exit == 0 ? out_str.strip() : "";
        } catch (Error e) { return ""; }
    }

    public static int sysfs_int(string name) {
        return int.parse(sysfs_str(name));
    }
}
