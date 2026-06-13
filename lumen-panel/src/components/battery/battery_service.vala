using GLib;

public class BatteryService : GLib.Object {

    private const uint POLL_SEC = 10;
    private const string SYSFS_DIR = "/sys/class/power_supply/BAT0/";
    private const string PSU_ROOT  = "/sys/class/power_supply/";

    public signal void state_changed();

    public string raw_status  = "";
    public int    percent     = 0;
    public float  voltage_v   = 0f;
    public float  current_a   = 0f;
    public int    charge_full = 0;
    public int    charge_now  = 0;
    public bool   ac_online   = false;

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
        ac_online   = read_ac_online();

        percent = (charge_full > 0)
            ? int.min(100, int.max(0, (int)((charge_now / (float) charge_full) * 100)))
            : 0;

        state_changed();
    }

    // Captures non-BAT0 setups (AC, ADP0/1, USB-C PD), so the panel can
    // reflect "wired to charger" even when the battery driver reports a
    // status other than "charging" (e.g. "full" while topped-off).
    private bool read_ac_online() {
        try {
            var dir = Dir.open(PSU_ROOT, 0);
            string? name;
            while ((name = dir.read_name()) != null) {
                if (name.has_prefix("BAT")) continue;
                string contents;
                try {
                    FileUtils.get_contents(PSU_ROOT + name + "/online", out contents);
                } catch (FileError e) { continue; }
                if (contents.strip() == "1") return true;
            }
        } catch (FileError e) { /* no power_supply dir */ }
        return false;
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
