using GLib;

public class Backends {

    public struct State {
        public double value;   // 0..1
        public bool   muted;
    }

    // Setters use run_capture, not spawn_detached: the follow-up query must
    // observe the new value.
    private static void set_sync(string[] argv) {
        LumenCommon.Proc.run_capture(argv);
    }

    // Keys cap at 100%: over-amplification is a Settings-slider choice. Relative
    // steps are kept where possible because an absolute value flattens balance.
    private static string raise_arg(int cur, int step) {
        return cur + step <= 100 ? "+%d%%".printf(step) : "%d%%".printf(int.max(cur, 100));
    }

    // From above 100% the first press lands straight on 100 - step instead of
    // grinding through steps the clamped OSD can't show.
    private static string lower_arg(int cur, int step) {
        return cur > 100 ? "%d%%".printf(100 - step) : "-%d%%".printf(step);
    }

    private static int current_percent(string what, string target) {
        return raw_percent(LumenCommon.Proc.run_capture(
            new string[]{ "pactl", "get-%s-volume".printf(what), target }) ?? "");
    }

    // The OSD value is computed from the pre-change read rather than re-queried:
    // raise is get + set + unmute (muted is then known false), lower is
    // get + set + get-mute. Mirrors raise_arg/lower_arg exactly.
    private static State volume_raise(string what, string target, int step) {
        int cur = current_percent(what, target);
        set_sync(new string[]{ "pactl", "set-%s-volume".printf(what), target, raise_arg(cur, step) });
        set_sync(new string[]{ "pactl", "set-%s-mute".printf(what), target, "0" });
        int now = cur + step <= 100 ? cur + step : int.max(cur, 100);
        return State() { value = clamp_unit(now), muted = false };
    }

    private static State volume_lower(string what, string target, int step) {
        int cur = current_percent(what, target);
        set_sync(new string[]{ "pactl", "set-%s-volume".printf(what), target, lower_arg(cur, step) });
        int now = cur > 100 ? 100 - step : cur - step;
        string? mute = LumenCommon.Proc.run_capture(
            new string[]{ "pactl", "get-%s-mute".printf(what), target });
        return State() { value = clamp_unit(now), muted = (mute ?? "").down().contains("yes") };
    }

    public static State output_volume_raise(int step) {
        return volume_raise("sink", "@DEFAULT_SINK@", step);
    }

    public static State output_volume_lower(int step) {
        return volume_lower("sink", "@DEFAULT_SINK@", step);
    }

    public static State output_volume_mute_toggle() {
        set_sync(new string[]{ "pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle" });
        return query_sink();
    }

    public static State query_sink() {
        string? vol = LumenCommon.Proc.run_capture(
            new string[]{ "pactl", "get-sink-volume", "@DEFAULT_SINK@" });
        string? mute = LumenCommon.Proc.run_capture(
            new string[]{ "pactl", "get-sink-mute", "@DEFAULT_SINK@" });
        return State() {
            value = parse_percent(vol ?? ""),
            muted = (mute ?? "").down().contains("yes")
        };
    }

    public static State input_volume_raise(int step) {
        return volume_raise("source", "@DEFAULT_SOURCE@", step);
    }

    public static State input_volume_lower(int step) {
        return volume_lower("source", "@DEFAULT_SOURCE@", step);
    }

    public static State input_volume_mute_toggle() {
        set_sync(new string[]{ "pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle" });
        return query_source();
    }

    public static State query_source() {
        string? vol = LumenCommon.Proc.run_capture(
            new string[]{ "pactl", "get-source-volume", "@DEFAULT_SOURCE@" });
        string? mute = LumenCommon.Proc.run_capture(
            new string[]{ "pactl", "get-source-mute", "@DEFAULT_SOURCE@" });
        return State() {
            value = parse_percent(vol ?? ""),
            muted = (mute ?? "").down().contains("yes")
        };
    }

    private static double parse_percent(string text) {
        return clamp_unit(raw_percent(text));
    }

    private static double clamp_unit(int percent) {
        return double.max(0, double.min(1.0, percent / 100.0));
    }

    // First "NN%" in pactl output, unclamped (over-amplified sinks read > 100).
    private static int raw_percent(string text) {
        try {
            var re = new Regex("([0-9]{1,3})%");
            MatchInfo info;
            int v = 0;
            if (re.match(text, 0, out info) && int.try_parse(info.fetch(1), out v)) return v;
        } catch (RegexError e) {}
        return 0;
    }

    // `brightnessctl -m set` prints the post-change CSV line itself, so one
    // spawn both sets and reports.
    public static State brightness_raise(int step) {
        return set_brightness(null, "%d%%+".printf(step));
    }
    public static State brightness_lower(int step) {
        return set_brightness(null, "%d%%-".printf(step));
    }
    public static State kbd_brightness_raise(int step) {
        return set_brightness("*::kbd_backlight", "%d%%+".printf(step));
    }
    public static State kbd_brightness_lower(int step) {
        return set_brightness("*::kbd_backlight", "%d%%-".printf(step));
    }

    private static State set_brightness(string? device, string value) {
        string[] argv = (device == null)
            ? new string[]{ "brightnessctl", "-m", "set", value }
            : new string[]{ "brightnessctl", "--device=" + (!) device, "-m", "set", value };
        string? raw = LumenCommon.Proc.run_capture(argv);
        // Format: name,class,current,pct,max  (pct includes %)
        var parts = (raw ?? "").strip().split(",");
        double v = 0.0;
        if (parts.length >= 4) {
            var pct_str = parts[3].replace("%", "").strip();
            int n = 0;
            if (int.try_parse(pct_str, out n))
                v = double.max(0, double.min(1.0, n / 100.0));
        }
        return State() { value = v, muted = false };
    }

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
