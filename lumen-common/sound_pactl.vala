using GLib;

public class SinkInfo : GLib.Object {
    public string id;
    public string name;

    public SinkInfo(string id, string name) {
        this.id   = id;
        this.name = name;
    }
}

public class SourceInfo : GLib.Object {
    public string id;
    public string name;
    public bool   monitor;

    public SourceInfo(string id, string name, bool monitor) {
        this.id      = id;
        this.name    = name;
        this.monitor = monitor;
    }
}

public class StreamInfo : GLib.Object {
    public string index;
    public string app_name;
    public int    volume_pct;
    public bool   muted;

    public StreamInfo(string index, string app_name, int volume_pct, bool muted) {
        this.index      = index;
        this.app_name   = app_name;
        this.volume_pct = volume_pct;
        this.muted      = muted;
    }
}

public class PactlClient : GLib.Object {

    // Our parec meter's stream name, so query_sink_inputs() can skip it.
    public const string METER_STREAM_NAME = "lumen-settings-meter";

    public string query_default_sink() {
        var out_str = run_pactl_sync({ "get-default-sink" }).strip();
        if (out_str != "") return out_str;

        out_str = run_pactl_sync({ "info" });
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
        var detailed  = run_pactl_sync({ "list", "sinks" });
        var desc_map  = parse_sink_descriptions(detailed);
        var out_str   = run_pactl_sync({ "list", "short", "sinks" });

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
        var out_str = run_pactl_sync({ "get-sink-volume", "@DEFAULT_SINK@" });
        int pct = first_percent(out_str);
        if (pct >= 0) return pct;

        out_str = run_wpctl_sync("@DEFAULT_AUDIO_SINK@");
        return parse_wpctl_percent(out_str);
    }

    public bool query_muted() {
        var out_str = run_pactl_sync({ "get-sink-mute", "@DEFAULT_SINK@" }).down();
        if (out_str.contains("yes")) return true;
        if (out_str.contains("no"))  return false;

        out_str = run_wpctl_sync("@DEFAULT_AUDIO_SINK@").down();
        return out_str.contains("muted");
    }

    public void set_volume(int pct) {
        pct = int.max(0, int.min(100, pct));
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-sink-volume", "@DEFAULT_SINK@", "%d%%".printf(pct)
        });
    }

    public void set_muted(bool muted) {
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"
        });
    }

    public void toggle_mute() {
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"
        });
    }

    public void set_default_sink(string sink_id) {
        if (sink_id == "") return;
        LumenCommon.Proc.spawn_detached(new string[] { "pactl", "set-default-sink", sink_id });
    }

    public string query_default_source() {
        var out_str = run_pactl_sync({ "get-default-source" }).strip();
        if (out_str != "") return out_str;

        out_str = run_pactl_sync({ "info" });
        foreach (var line in out_str.split("\n")) {
            var l = line.strip();
            if (l.has_prefix("Default Source:")) {
                return l.substring("Default Source:".length).strip();
            }
        }
        return "";
    }

    public SourceInfo[] query_sources() {
        SourceInfo[] result = {};
        var detailed = run_pactl_sync({ "list", "sources" });
        var desc_map = parse_sink_descriptions(detailed);
        var out_str  = run_pactl_sync({ "list", "short", "sources" });

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

            bool monitor = id.has_suffix(".monitor");
            result += new SourceInfo(id, name, monitor);
        }
        return result;
    }

    public void set_default_source(string source_id) {
        if (source_id == "") return;
        LumenCommon.Proc.spawn_detached(new string[] { "pactl", "set-default-source", source_id });
    }

    public int query_input_volume_percent() {
        var out_str = run_pactl_sync({ "get-source-volume", "@DEFAULT_SOURCE@" });
        int pct = first_percent(out_str);
        if (pct >= 0) return pct;

        out_str = run_wpctl_sync("@DEFAULT_AUDIO_SOURCE@");
        return parse_wpctl_percent(out_str);
    }

    public bool query_input_muted() {
        var out_str = run_pactl_sync({ "get-source-mute", "@DEFAULT_SOURCE@" }).down();
        if (out_str.contains("yes")) return true;
        if (out_str.contains("no"))  return false;

        out_str = run_wpctl_sync("@DEFAULT_AUDIO_SOURCE@").down();
        return out_str.contains("muted");
    }

    public void set_input_volume(int pct) {
        pct = int.max(0, int.min(100, pct));
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-source-volume", "@DEFAULT_SOURCE@", "%d%%".printf(pct)
        });
    }

    public void set_input_muted(bool muted) {
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-source-mute", "@DEFAULT_SOURCE@", muted ? "1" : "0"
        });
    }

    public void toggle_input_mute() {
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"
        });
    }

    public void set_sink_volume_by_id(string id, int pct, int max = 100) {
        if (id == "") return;
        pct = int.max(0, int.min(max, pct));
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-sink-volume", id, "%d%%".printf(pct)
        });
    }

    public StreamInfo[] query_sink_inputs() {
        StreamInfo[] result = {};
        var text = run_pactl_sync({ "list", "sink-inputs" });

        foreach (var block in text.split("Sink Input #")) {
            var b = block.strip();
            if (b == "") continue;

            var lines = block.split("\n");
            string index = lines[0].strip();
            if (index == "" || !index[0].isdigit()) continue;

            bool muted = false;
            int vol = -1;
            string app_name = "";
            string media_name = "";
            string binary = "";
            bool in_props = false;

            foreach (var raw in lines) {
                var l = raw.strip();
                if (l.has_prefix("Properties:")) { in_props = true; continue; }

                if (!in_props) {
                    if (l.has_prefix("Mute:")) {
                        muted = l.down().contains("yes");
                    } else if (l.has_prefix("Volume:")) {
                        int p = first_percent(l);
                        if (p >= 0) vol = p;
                    }
                } else {
                    if (l.has_prefix("application.name")) {
                        app_name = prop_value(l);
                    } else if (l.has_prefix("media.name")) {
                        media_name = prop_value(l);
                    } else if (l.has_prefix("application.process.binary")) {
                        binary = prop_value(l);
                    }
                }
            }

            string name = app_name;
            if (name == "") name = media_name;
            if (name == "") name = binary;
            if (name == "") name = "Application";
            if (name.contains(METER_STREAM_NAME)) continue;

            result += new StreamInfo(index, name, vol < 0 ? 0 : vol, muted);
        }
        return result;
    }

    public void set_sink_input_volume(string index, int pct) {
        if (index == "") return;
        pct = int.max(0, int.min(150, pct));
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-sink-input-volume", index, "%d%%".printf(pct)
        });
    }

    public void set_sink_input_muted(string index, bool muted) {
        if (index == "") return;
        LumenCommon.Proc.spawn_detached(new string[] {
            "pactl", "set-sink-input-mute", index, muted ? "1" : "0"
        });
    }

    private string prop_value(string line) {
        int eq = line.index_of("=");
        if (eq < 0) return "";
        var v = line.substring(eq + 1).strip();
        if (v.has_prefix("\"") && v.has_suffix("\"") && v.length >= 2)
            v = v.substring(1, v.length - 2);
        return v;
    }

    // Output is parsed by English field prefixes, so pin the locale.
    private const string[] C_LOCALE = { "LC_ALL=C" };

    private string run_pactl_sync(string[] args) {
        string[] argv = { "pactl" };
        foreach (var a in args) argv += a;
        return LumenCommon.Proc.run_capture(argv, C_LOCALE) ?? "";
    }

    private string run_wpctl_sync(string target) {
        return LumenCommon.Proc.run_capture(
            new string[] { "wpctl", "get-volume", target }, C_LOCALE) ?? "";
    }

    // pactl: "front-left: 45874 /  70% / -9.35 dB". -1 when none.
    private int first_percent(string text) {
        for (int pct = text.index_of_char('%'); pct > 0;
             pct = text.index_of_char('%', pct + 1)) {
            int start = pct;
            while (start > 0 && text[start - 1].isdigit()) start--;
            if (start < pct)
                return int.max(0, int.min(100, int.parse(text.substring(start, pct - start))));
        }
        return -1;
    }

    // wpctl: "Volume: 0.70 [MUTED]". double.try_parse is locale-independent.
    private int parse_wpctl_percent(string text) {
        int i = 0;
        while (i < text.length && !text[i].isdigit()) i++;
        int start = i;
        while (i < text.length && (text[i].isdigit() || text[i] == '.')) i++;
        if (start == i) return 0;

        double v = 0;
        if (!double.try_parse(text.substring(start, i - start), out v)) return 0;
        return int.max(0, int.min(100, (int)(v * 100.0)));
    }

    private GLib.HashTable<string, string> parse_sink_descriptions(string text) {
        var map = new GLib.HashTable<string, string>(str_hash, str_equal);
        string current_name = "";
        string current_desc = "";

        foreach (var raw in text.split("\n")) {
            string line = raw.strip();
            if (line.has_prefix("Name:")) {
                if (current_name != "" && current_desc != "")
                    map.insert(current_name, current_desc);
                int sep = line.index_of(":");
                current_name = sep >= 0 ? line.substring(sep + 1).strip() : "";
                current_desc = "";
                continue;
            }
            if (line.has_prefix("Description:")) {
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
