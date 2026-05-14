using GLib;

/**
 * Watches sysfs brightness files for the screen backlight and keyboard
 * backlight, and pops the OSD whenever either value changes — regardless of
 * what caused the change (Fn key handled by the EC, brightnessctl from
 * lumen-osdctl, KDE's slider, idle dimming, etc).
 *
 * Necessary because on most laptops the embedded controller adjusts the
 * keyboard backlight directly via firmware without emitting a KEY_KBDILLUM*
 * event to userspace, so a key-binding in Wayfire never fires.
 */
public class BrightnessWatcher : Object {

    private OsdService service;

    private string? kbd_path    = null;
    private int     kbd_max     = 0;
    private int     kbd_last    = -1;

    private string? screen_path = null;
    private int     screen_max  = 0;
    private int     screen_last = -1;

    private bool primed = false;

    public BrightnessWatcher(OsdService service) {
        this.service = service;
        discover_kbd();
        discover_screen();
        // sysfs brightness writes don't reliably emit inotify events, so a
        // tiny periodic read is the most portable trigger. 200ms is fast
        // enough to feel instant for keypress-driven changes.
        Timeout.add(200, this.tick);
    }

    private void discover_kbd() {
        try {
            var dir = Dir.open("/sys/class/leds");
            string? name = null;
            while ((name = dir.read_name()) != null) {
                if (!((!) name).has_suffix("::kbd_backlight")) continue;
                kbd_path = "/sys/class/leds/" + (!) name + "/brightness";
                kbd_max  = read_int("/sys/class/leds/" + (!) name + "/max_brightness");
                break;
            }
        } catch (Error e) {}
    }

    private void discover_screen() {
        try {
            var dir = Dir.open("/sys/class/backlight");
            string? name = null;
            while ((name = dir.read_name()) != null) {
                string base_path = "/sys/class/backlight/" + (!) name;
                if (!FileUtils.test(base_path + "/brightness", FileTest.EXISTS)) continue;
                screen_path = base_path + "/brightness";
                screen_max  = read_int(base_path + "/max_brightness");
                break;
            }
        } catch (Error e) {}
    }

    private bool tick() {
        int kbd_now    = (kbd_path    != null) ? read_int((!) kbd_path)    : -1;
        int screen_now = (screen_path != null) ? read_int((!) screen_path) : -1;

        if (!primed) {
            kbd_last    = kbd_now;
            screen_last = screen_now;
            primed = true;
            return Source.CONTINUE;
        }

        if (kbd_now >= 0 && kbd_now != kbd_last && kbd_max > 0) {
            kbd_last = kbd_now;
            present("kbd-brightness", (double) kbd_now / kbd_max);
        }
        if (screen_now >= 0 && screen_now != screen_last && screen_max > 0) {
            screen_last = screen_now;
            present("brightness", (double) screen_now / screen_max);
        }
        return Source.CONTINUE;
    }

    private void present(string kind, double frac) {
        string txt = "%d%%".printf((int) Math.round(frac * 100));
        var opts = new HashTable<string, Variant>(str_hash, str_equal);
        try {
            service.show(kind, frac, txt, opts);
        } catch (Error e) {
            // Watcher must never crash the daemon.
        }
    }

    private static int read_int(string path) {
        string contents = "";
        if (FileUtils.get_contents(path, out contents)) {
            int n = 0;
            if (int.try_parse(contents.strip(), out n)) return n;
        }
        return -1;
    }
}
