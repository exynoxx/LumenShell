using GLib;

public class Backends {

    public struct State {
        public double value;   // 0..1
        public bool   muted;
    }

    // ---- shared helpers ----

    private static string run_sync(string cmd) {
        string outp = "";
        try {
            Process.spawn_command_line_sync(cmd, out outp, null, null);
        } catch (SpawnError e) {
            return "";
        }
        return outp;
    }

    private static void run_async(string cmd) {
        try {
            Process.spawn_command_line_async(cmd);
        } catch (SpawnError e) {}
    }

    // ---- pactl: sink (output volume) ----

    public static State output_volume_raise(int step) {
        run_sync("pactl set-sink-volume @DEFAULT_SINK@ +%d%%".printf(step));
        run_sync("pactl set-sink-mute   @DEFAULT_SINK@ 0");
        return query_sink();
    }

    public static State output_volume_lower(int step) {
        run_sync("pactl set-sink-volume @DEFAULT_SINK@ -%d%%".printf(step));
        return query_sink();
    }

    public static State output_volume_mute_toggle() {
        run_sync("pactl set-sink-mute @DEFAULT_SINK@ toggle");
        return query_sink();
    }

    public static State query_sink() {
        return State() {
            value = parse_percent(run_sync(
                "env LC_ALL=C pactl get-sink-volume @DEFAULT_SINK@")),
            muted = run_sync(
                "env LC_ALL=C pactl get-sink-mute @DEFAULT_SINK@").down().contains("yes")
        };
    }

    // ---- pactl: source (mic) ----

    public static State input_volume_raise(int step) {
        run_sync("pactl set-source-volume @DEFAULT_SOURCE@ +%d%%".printf(step));
        run_sync("pactl set-source-mute   @DEFAULT_SOURCE@ 0");
        return query_source();
    }

    public static State input_volume_lower(int step) {
        run_sync("pactl set-source-volume @DEFAULT_SOURCE@ -%d%%".printf(step));
        return query_source();
    }

    public static State input_volume_mute_toggle() {
        run_sync("pactl set-source-mute @DEFAULT_SOURCE@ toggle");
        return query_source();
    }

    public static State query_source() {
        return State() {
            value = parse_percent(run_sync(
                "env LC_ALL=C pactl get-source-volume @DEFAULT_SOURCE@")),
            muted = run_sync(
                "env LC_ALL=C pactl get-source-mute @DEFAULT_SOURCE@").down().contains("yes")
        };
    }

    private static double parse_percent(string text) {
        try {
            var re = new Regex("([0-9]{1,3})%");
            MatchInfo info;
            if (re.match(text, 0, out info)) {
                int v = 0;
                if (int.try_parse(info.fetch(1), out v))
                    return double.max(0, double.min(1.0, v / 100.0));
            }
        } catch (RegexError e) {}
        return 0;
    }

    // ---- brightnessctl ----

    public static State brightness_raise(int step) {
        run_sync("brightnessctl set %d%%+".printf(step));
        return query_brightness("");
    }
    public static State brightness_lower(int step) {
        run_sync("brightnessctl set %d%%-".printf(step));
        return query_brightness("");
    }
    public static State kbd_brightness_raise(int step) {
        run_sync("brightnessctl --device='*::kbd_backlight' set %d%%+".printf(step));
        return query_brightness("--device='*::kbd_backlight'");
    }
    public static State kbd_brightness_lower(int step) {
        run_sync("brightnessctl --device='*::kbd_backlight' set %d%%-".printf(step));
        return query_brightness("--device='*::kbd_backlight'");
    }

    private static State query_brightness(string device_arg) {
        var raw = run_sync("brightnessctl %s -m".printf(device_arg));
        // Format: name,class,current,pct,max  (pct includes %)
        var parts = raw.strip().split(",");
        double v = 0.0;
        if (parts.length >= 4) {
            var pct_str = parts[3].replace("%", "").strip();
            int n = 0;
            if (int.try_parse(pct_str, out n))
                v = double.max(0, double.min(1.0, n / 100.0));
        }
        return State() { value = v, muted = false };
    }

    // ---- caps lock (sysfs) ----

    public static bool caps_lock_on() {
        try {
            var dir = Dir.open("/sys/class/leds");
            string? name = null;
            while ((name = dir.read_name()) != null) {
                if (!name.has_suffix("::capslock")) continue;
                string path = "/sys/class/leds/" + name + "/brightness";
                string contents = "";
                if (FileUtils.get_contents(path, out contents)) {
                    return contents.strip() != "0";
                }
            }
        } catch (Error e) {}
        return false;
    }
}
