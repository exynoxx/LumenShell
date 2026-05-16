using GLib;

/**
 * BatteryService — single sysfs read path shared by BatteryTray and BatteryPage.
 *
 * Polls every 10 s after construction; state_changed fires on each refresh.
 */
public class BatteryService : GLib.Object {

    private const uint POLL_SEC = 10;
    private const string SYSFS_DIR = "/sys/class/power_supply/BAT0/";

    public signal void state_changed();

    public string raw_status  = "";
    public int    percent     = 0;
    public float  voltage_v   = 0f;
    public float  current_a   = 0f;
    public int    charge_full = 0;
    public int    charge_now  = 0;

    public BatteryService() {
        refresh();
        GLib.Timeout.add_seconds(POLL_SEC, () => {
            refresh();
            return Source.CONTINUE;
        });
    }

    public void refresh() {
        raw_status  = sysfs_str("status").down().strip();
        charge_full = sysfs_int("charge_full");
        charge_now  = sysfs_int("charge_now");
        voltage_v   = sysfs_int("voltage_now") / 1000000f;
        current_a   = sysfs_int("current_now") / 1000000f;

        percent = (charge_full > 0)
            ? int.min(100, int.max(0, (int)((charge_now / (float) charge_full) * 100)))
            : 0;

        state_changed();
    }

    static string sysfs_str(string name) {
        try {
            string contents;
            FileUtils.get_contents(SYSFS_DIR + name, out contents);
            return contents.strip();
        } catch (FileError e) {
            return "";
        }
    }

    static int sysfs_int(string name) {
        return int.parse(sysfs_str(name));
    }
}
