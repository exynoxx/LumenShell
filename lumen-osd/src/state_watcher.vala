// Firmware changes the kbd backlight without a keypress, and Wayfire's
// KEY_CAPSLOCK binding misses the press that turns CapsLock OFF — so poll.
// Exception: the kbd LED's brightness_hw_changed is poll()able, and reading
// brightness on Dell costs a ~4 ms SMM call, so watch that instead when present.
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
        discover(out kbd_path,    out kbd_max,    "/sys/class/leds",      "::kbd_backlight", true);
        discover(out screen_path, out screen_max, "/sys/class/backlight", null,              true);
        int _unused;
        discover(out caps_path,   out _unused,    "/sys/class/leds",      "::capslock",      false);

        if (kbd_path != null) watch_kbd_hw_changed();

        // sysfs writes don't reliably emit inotify. Don't arm with nothing to
        // read, or a desktop wakes every second forever.
        if (kbd_path != null || screen_path != null || caps_path != null)
            Timeout.add(500, this.tick);
    }

    // Fires only on firmware-initiated changes (Fn keys); software writes come
    // through lumen-osdctl's DBus call anyway. Reads ENODATA until the first
    // hw change — the read still rearms poll(), so errors are just ignored.
    private void watch_kbd_hw_changed() {
        string hw_path = Path.get_dirname((!) kbd_path) + "/brightness_hw_changed";
        if (!FileUtils.test(hw_path, FileTest.EXISTS)) return;
        try {
            var ch = new IOChannel.file(hw_path, "r");
            ch.set_encoding(null);
            read_channel_int(ch);
            ch.add_watch(IOCondition.PRI | IOCondition.ERR, () => {
                int now = read_channel_int(ch);
                if (now >= 0 && kbd_max > 0)
                    present_slider("kbd-brightness", (double) now / kbd_max);
                return Source.CONTINUE;
            });
            kbd_path = null;  // stop polling the expensive brightness file
        } catch (Error e) {}
    }

    private static int read_channel_int(IOChannel ch) {
        try {
            ch.seek_position(0, SeekType.SET);
            string? line = null;
            size_t len, term;
            ch.read_line(out line, out len, out term);
            int n = 0;
            if (line != null && int.try_parse(((!) line).strip(), out n)) return n;
        } catch (Error e) {}
        return -1;
    }

    private static void discover(out string? path, out int max,
                                 string parent, string? suffix,
                                 bool read_max) {
        path = null;
        max  = 0;
        try {
            var dir = Dir.open(parent);
            string? name = null;
            while ((name = dir.read_name()) != null) {
                string entry = (!) name;
                string base_path = parent + "/" + entry;
                if (suffix != null) {
                    if (!entry.has_suffix((!) suffix)) continue;
                } else {
                    if (!FileUtils.test(base_path + "/brightness", FileTest.EXISTS)) continue;
                }
                path = base_path + "/brightness";
                if (read_max) max = read_int(base_path + "/max_brightness");
                return;
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

    // Empty text: Presenter formats the percentage itself.
    private void present_slider(string kind, double frac) {
        var opts = new HashTable<string, Variant>(str_hash, str_equal);
        try {
            service.show(kind, frac, "", opts);
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
        try {
            if (FileUtils.get_contents(path, out contents)) {
                int n = 0;
                if (int.try_parse(contents.strip(), out n)) return n;
            }
        } catch (FileError e) {}  // LED vanished (e.g. USB keyboard unplugged)
        return -1;
    }
}
