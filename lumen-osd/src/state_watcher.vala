using GLib;

/**
 * Polls sysfs for the screen backlight, keyboard backlight, and CapsLock LED,
 * and pops the OSD whenever any of them changes — regardless of cause.
 *
 * Needed because the laptop EC adjusts the keyboard backlight directly via
 * firmware (no keypress reaches Wayfire), and because Wayfire's
 * binding_capslock = KEY_CAPSLOCK doesn't match the press that turns CapsLock
 * OFF (the CapsLock modifier is active during that press, so the modifier-less
 * binding silently does not fire).
 */
public class StateWatcher : Object {

    private OsdService service;

    private string? kbd_path    = null;
    private int     kbd_max     = 0;
    private int     kbd_last    = -1;

    private string? screen_path = null;
    private int     screen_max  = 0;
    private int     screen_last = -1;

    private string? caps_path   = null;
    private int     caps_last   = -1;

    private bool primed = false;

    public StateWatcher(OsdService service) {
        this.service = service;
        discover_kbd();
        discover_screen();
        discover_caps();
        // sysfs writes don't reliably emit inotify, so a short periodic
        // read is the most portable trigger. 200ms feels instant.
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

    private void discover_caps() {
        try {
            var dir = Dir.open("/sys/class/leds");
            string? name = null;
            while ((name = dir.read_name()) != null) {
                if (!((!) name).has_suffix("::capslock")) continue;
                caps_path = "/sys/class/leds/" + (!) name + "/brightness";
                break;
            }
        } catch (Error e) {}
    }

    private bool tick() {
        int kbd_now    = (kbd_path    != null) ? read_int((!) kbd_path)    : -1;
        int screen_now = (screen_path != null) ? read_int((!) screen_path) : -1;
        int caps_now   = (caps_path   != null) ? read_int((!) caps_path)   : -1;

        if (!primed) {
            kbd_last    = kbd_now;
            screen_last = screen_now;
            caps_last   = caps_now;
            primed = true;
            return Source.CONTINUE;
        }

        if (kbd_now >= 0 && kbd_now != kbd_last && kbd_max > 0) {
            kbd_last = kbd_now;
            present_slider("kbd-brightness", (double) kbd_now / kbd_max);
        }
        if (screen_now >= 0 && screen_now != screen_last && screen_max > 0) {
            screen_last = screen_now;
            present_slider("brightness", (double) screen_now / screen_max);
        }
        if (caps_now >= 0 && caps_now != caps_last) {
            caps_last = caps_now;
            present_chip("caps-lock", caps_now != 0 ? "Caps ON" : "Caps OFF");
        }
        return Source.CONTINUE;
    }

    private void present_slider(string kind, double frac) {
        string txt = "%d%%".printf((int) Math.round(frac * 100));
        var opts = new HashTable<string, Variant>(str_hash, str_equal);
        try {
            service.show(kind, frac, txt, opts);
        } catch (Error e) {}
    }

    private void present_chip(string kind, string text) {
        var opts = new HashTable<string, Variant>(str_hash, str_equal);
        try {
            service.show(kind, 0.0, text, opts);
        } catch (Error e) {}
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
