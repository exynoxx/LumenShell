using GLib;

// Reads sysfs directly (cheap, no subprocess); writes via brightnessctl, which
// carries the udev permissions to touch the backlight.
public class BrightnessService : GLib.Object {

    public signal void changed ();

    public bool available { get; private set; default = false; }
    public int  percent   { get; private set; default = 0; }

    string dir = "";
    int    max = 0;

    private const uint POLL_MS = 1000;

    public BrightnessService () {
        detect ();
        if (!available) return;
        read ();
        GLib.Timeout.add (POLL_MS, () => { read (); return Source.CONTINUE; });
    }

    void detect () {
        try {
            var bl = File.new_for_path ("/sys/class/backlight");
            var en = bl.enumerate_children ("standard::name", FileQueryInfoFlags.NONE);
            FileInfo info;
            while ((info = en.next_file ()) != null) {
                string d = "/sys/class/backlight/" + info.get_name ();
                int m = read_int (d + "/max_brightness");
                if (m > 0) { dir = d; max = m; available = true; return; }
            }
        } catch (Error e) {
            // No backlight class (desktop / VM) — stay unavailable.
        }
    }

    void read () {
        if (!available) return;
        int cur = read_int (dir + "/brightness");
        int pct = (int) Math.round ((double) cur / max * 100.0);
        pct = pct.clamp (1, 100);
        if (pct == percent) return;
        percent = pct;
        changed ();
    }

    // Never drives the panel fully dark from the slider — clamp the low end to 1%.
    public void set_level (int pct) {
        if (!available) return;
        pct = pct.clamp (1, 100);
        percent = pct;
        LumenCommon.Proc.spawn_detached (new string[] {
            "brightnessctl", "set", "%d%%".printf (pct)
        });
    }

    int read_int (string path) {
        string contents;
        try {
            if (!FileUtils.get_contents (path, out contents)) return 0;
        } catch (Error e) {
            return 0;
        }
        return int.parse (contents.strip ());
    }
}
