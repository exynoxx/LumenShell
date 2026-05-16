using GLib;

/**
 * SinkInfo — data record for one audio output device.
 */
public class SinkInfo : GLib.Object {
    public string id;
    public string name;

    public SinkInfo(string id, string name) {
        this.id   = id;
        this.name = name;
    }
}

/**
 * PactlClient — all pactl / wpctl shelling and parsing in one place.
 *
 * Exposes audio verbs (set_volume, toggle_mute, …). Callers never see
 * a shell command or the @DEFAULT_SINK@ token.
 */
public class PactlClient : GLib.Object {

    public string query_default_sink() {
        var out_str = run_pactl_sync("get-default-sink").strip();
        if (out_str != "") return out_str;

        out_str = run_pactl_sync("info");
        foreach (var line in out_str.split("\n")) {
            var l = line.strip();
            if (l.has_prefix("Default Sink:")) {
                return l.substring("Default Sink:".length).strip();
            }
        }
        return "";
    }

    public SinkInfo[] query_sinks() {
        SinkInfo[] result = {};
        var detailed  = run_pactl_sync("list sinks");
        var desc_map  = parse_sink_descriptions(detailed);
        var out_str   = run_pactl_sync("list short sinks");

        foreach (var line in out_str.split("\n")) {
            var l = line.strip();
            if (l == "") continue;
            var p = l.split("\t");
            if (p.length < 2) continue;

            string id = p[1];
            string? from_desc = desc_map.lookup(id);
            string name = (from_desc != null && from_desc.strip() != "")
                ? from_desc.strip()
                : pretty_sink_name(id);

            result += new SinkInfo(id, name);
        }
        return result;
    }

    public int query_volume_percent() {
        var out_str = run_pactl_sync("get-sink-volume @DEFAULT_SINK@");
        int pct = first_percent(out_str);
        if (pct >= 0) return pct;

        out_str = run_cmd_sync("wpctl get-volume @DEFAULT_AUDIO_SINK@");
        return parse_wpctl_percent(out_str);
    }

    public bool query_muted() {
        var out_str = run_pactl_sync("get-sink-mute @DEFAULT_SINK@").down();
        if (out_str.contains("yes")) return true;
        if (out_str.contains("no"))  return false;

        out_str = run_cmd_sync("wpctl get-volume @DEFAULT_AUDIO_SINK@").down();
        return out_str.contains("muted");
    }

    public void set_volume(int pct) {
        pct = int.max(0, int.min(100, pct));
        Utils.spawn_argv(new string[] {
            "pactl", "set-sink-volume", "@DEFAULT_SINK@", "%d%%".printf(pct)
        });
    }

    public void set_muted(bool muted) {
        Utils.spawn_argv(new string[] {
            "pactl", "set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"
        });
    }

    public void toggle_mute() {
        Utils.spawn_argv(new string[] {
            "pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"
        });
    }

    public void set_default_sink(string sink_id) {
        if (sink_id == "") return;
        Utils.spawn_argv(new string[] { "pactl", "set-default-sink", sink_id });
    }

    private string run_cmd_sync(string cmd) {
        string out_str = "";
        try {
            Process.spawn_command_line_sync(cmd, out out_str, null, null);
        } catch (SpawnError e) {
            return "";
        }
        return out_str;
    }

    private string run_pactl_sync(string args) {
        return run_cmd_sync("env LC_ALL=C pactl " + args);
    }

    private int first_percent(string text) {
        try {
            var re = new Regex("([0-9]{1,3})%");
            MatchInfo info;
            if (re.match(text, 0, out info)) {
                var s = info.fetch(1);
                int v = 0;
                if (int.try_parse(s, out v))
                    return int.max(0, int.min(100, v));
            }
        } catch (RegexError e) {}
        return -1;
    }

    private int parse_wpctl_percent(string text) {
        try {
            var re = new Regex("([0-9]+(?:\\.[0-9]+)?)");
            MatchInfo info;
            if (re.match(text, 0, out info)) {
                var s = info.fetch(1);
                double v = 0;
                if (double.try_parse(s, out v)) {
                    int pct = (int)(v * 100.0);
                    return int.max(0, int.min(100, pct));
                }
            }
        } catch (RegexError e) {}
        return 0;
    }

    private GLib.HashTable<string, string> parse_sink_descriptions(string text) {
        var map = new GLib.HashTable<string, string>(str_hash, str_equal);
        string current_name = "";
        string current_desc = "";

        foreach (var raw in text.split("\n")) {
            string line = raw.strip();
            if (line.has_prefix("Name:") || line.has_prefix("Navn:")) {
                if (current_name != "" && current_desc != "")
                    map.insert(current_name, current_desc);
                int sep = line.index_of(":");
                current_name = sep >= 0 ? line.substring(sep + 1).strip() : "";
                current_desc = "";
                continue;
            }
            if (line.has_prefix("Description:") || line.has_prefix("Beskrivelse:")) {
                int sep = line.index_of(":");
                current_desc = sep >= 0 ? line.substring(sep + 1).strip() : "";
                continue;
            }
        }

        if (current_name != "" && current_desc != "")
            map.insert(current_name, current_desc);

        return map;
    }

    private string pretty_sink_name(string sink_id) {
        string s = sink_id;
        if (s.has_prefix("alsa_output."))
            s = s.substring("alsa_output.".length);

        s = s.replace(".analog-stereo", "");
        s = s.replace(".analog-surround-21", "");
        s = s.replace(".analog-surround-40", "");
        s = s.replace(".analog-surround-51", "");
        s = s.replace(".hdmi-stereo", " HDMI");
        s = s.replace(".iec958-stereo", " Digital");
        s = s.replace("_", " ");
        s = s.replace(".", " ");

        if (s.length == 0) return sink_id;
        return s;
    }
}
