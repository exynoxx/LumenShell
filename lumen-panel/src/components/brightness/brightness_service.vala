// Reads sysfs directly (cheap, no subprocess); writes via brightnessctl, which
// carries the udev permissions to touch the backlight.
// FreeBSD: backlight(9) ioctls on /dev/backlight/backlightN for both read and
// write (0..100, group `video`), no subprocess.
public class BrightnessService : GLib.Object {

    public signal void changed ();

    public bool available { get; private set; default = false; }
    public int  percent   { get; private set; default = 0; }

    string dir = "";
    int    max = 0;

    private const uint POLL_MS = 1000;

    uint watchers   = 0;
    uint poll_timer = 0;
    LumenCommon.Coalescer writer;

    public BrightnessService () {
        writer = new LumenCommon.Coalescer ((pct) => {
#if FREEBSD
            LumenCommon.Bsd.Backlight.set_percent (dir, pct);
#else
            // -d: the device read() reads, not brightnessctl's default.
            LumenCommon.Proc.spawn_detached (new string[] {
                "brightnessctl", "-d", Path.get_basename (dir), "set", "%d%%".printf (pct)
            });
#endif
        });
        detect ();
        if (available) read ();
    }

    // Polled only while a slider is mapped (sysfs has no inotify).
    public void watch () {
        if (!available || watchers++ > 0) return;
        read ();
        poll_timer = GLib.Timeout.add (POLL_MS, () => { read (); return Source.CONTINUE; });
    }

    public void unwatch () {
        if (watchers == 0 || --watchers > 0) return;
        GLib.Source.remove (poll_timer);
        poll_timer = 0;
    }

    void detect () {
#if FREEBSD
        var dev = LumenCommon.Bsd.Backlight.first_device ();
        if (dev != null && LumenCommon.Bsd.Backlight.get_percent ((!) dev) >= 0) {
            dir = (!) dev; max = 100; available = true;
        }
        return;
#endif
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
        if (!available || writer.busy) return;
#if FREEBSD
        int cur = LumenCommon.Bsd.Backlight.get_percent (dir);
        if (cur < 0) return;
#else
        int cur = read_int (dir + "/brightness");
#endif
        int pct = (int) Math.round ((double) cur / max * 100.0);
        pct = pct.clamp (1, 100);
        if (pct == percent) return;
        percent = pct;
        changed ();
    }

    // Never drives the panel fully dark from the slider — clamp the low end to 1%.
    public void set_level (int pct) {
        pct = pct.clamp (1, 100);
        percent = pct;
        writer.push (pct);
    }

    int read_int (string path) {
        string contents;
        try {
            FileUtils.get_contents (path, out contents);
        } catch (Error e) {
            return 0;
        }
        return int.parse (contents.strip ());
    }
}
