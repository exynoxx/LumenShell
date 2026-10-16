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

// One snapshot of everything SoundService shows.
public class PactlState : GLib.Object {
    public string       default_sink         = "";
    public SinkInfo[]   sinks                = {};
    public int          volume_percent       = 0;
    public bool         muted                = false;
    public string       default_source       = "";
    public SourceInfo[] sources              = {};
    public int          input_volume_percent = 0;
    public bool         input_muted          = false;
    public StreamInfo[] sink_inputs          = {};
}

public class PactlClient : GLib.Object {

    // Our parec meter's stream name, so query_state() can skip it.
    public const string METER_STREAM_NAME = "lumen-settings-meter";

    // Two spawns (`pactl info` + `pactl list`) per pass. Text output, not
    // `-f json`: pactl's JSON writer drops non-ASCII strings as "(null)".
    // Falls back to the per-field get-*/wpctl queries only when the default
    // device isn't in the list (no server, or a race with a hotplug).
    public PactlState query_state() {
        var st = new PactlState();
        foreach (var line in run_pactl_sync({ "info" }).split("\n")) {
            var l = line.strip();
            if (l.has_prefix("Default Sink:"))
                st.default_sink = l.substring("Default Sink:".length).strip();
            else if (l.has_prefix("Default Source:"))
                st.default_source = l.substring("Default Source:".length).strip();
        }

        SinkInfo[]   sinks   = {};
        SourceInfo[] sources = {};
        StreamInfo[] inputs  = {};
        bool sink_found = false, source_found = false;
        foreach (var block in list_sections(run_pactl_sync({ "list" }))) {
            string id, desc;
            int vol;
            bool mute;
            if (block.has_prefix("Sink #")) {
                parse_device(block, out id, out desc, out vol, out mute);
                if (id == "") continue;
                sinks += new SinkInfo(id, desc != "" ? desc : pretty_sink_name(id));
                if (id == st.default_sink && vol >= 0) {
                    st.volume_percent = vol;
                    st.muted = mute;
                    sink_found = true;
                }
            } else if (block.has_prefix("Source #")) {
                parse_device(block, out id, out desc, out vol, out mute);
                if (id == "") continue;
                sources += new SourceInfo(id, desc != "" ? desc : pretty_sink_name(id),
                                             id.has_suffix(".monitor"));
                if (id == st.default_source && vol >= 0) {
                    st.input_volume_percent = vol;
                    st.input_muted = mute;
                    source_found = true;
                }
            } else if (block.has_prefix("Sink Input #")) {
                var s = parse_sink_input(block);
                if (s != null) inputs += s;
            }
        }
        st.sinks       = sinks;
        st.sources     = sources;
        st.sink_inputs = inputs;

        if (!sink_found) {
            st.volume_percent = query_volume_percent();
            st.muted          = query_muted();
        }
        if (!source_found) {
            st.input_volume_percent = query_input_volume_percent();
            st.input_muted          = query_input_muted();
        }
        return st;
    }

    // `pactl list` → top-level blocks, each starting at its unindented "Kind #N" header.
    private string[] list_sections(string text) {
        string[] blocks = {};
        var cur = new StringBuilder();
        foreach (var line in text.split("\n")) {
            if (line != "" && !line[0].isspace() && line.contains(" #") && cur.len > 0) {
                blocks += cur.str;
                cur.truncate(0);
            }
            cur.append(line);
            cur.append_c('\n');
        }
        if (cur.len > 0) blocks += cur.str;
        return blocks;
    }

    // Sink/Source block. vol is -1 when no "Volume:" percent was found.
    private void parse_device(string block, out string id, out string desc,
                              out int vol, out bool mute) {
        id = ""; desc = ""; vol = -1; mute = false;
        bool seen_mute = false;
        foreach (var raw in block.split("\n")) {
            var l = raw.strip();
            if (id == "" && l.has_prefix("Name:"))
                id = l.substring("Name:".length).strip();
            else if (desc == "" && l.has_prefix("Description:"))
                desc = l.substring("Description:".length).strip();
            else if (!seen_mute && l.has_prefix("Mute:")) {
                mute = l.down().contains("yes");
                seen_mute = true;
            } else if (vol < 0 && l.has_prefix("Volume:"))
                vol = first_percent(l);
        }
    }

    private StreamInfo? parse_sink_input(string block) {
        var lines = block.split("\n");
        string index = lines[0].substring(lines[0].index_of_char('#') + 1).strip();
        if (index == "" || !index[0].isdigit()) return null;

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
        if (name.contains(METER_STREAM_NAME)) return null;

        return new StreamInfo(index, name, vol < 0 ? 0 : vol, muted);
    }

    // max > 100 reports over-amplification instead of clamping it away.
    public int query_volume_percent(int max = 100) {
        var out_str = run_pactl_sync({ "get-sink-volume", "@DEFAULT_SINK@" });
        int pct = first_percent(out_str, max);
        if (pct >= 0) return pct;

        out_str = run_wpctl_sync("@DEFAULT_AUDIO_SINK@");
        return parse_wpctl_percent(out_str, max);
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
    private int first_percent(string text, int max = 100) {
        for (int pct = text.index_of_char('%'); pct > 0;
             pct = text.index_of_char('%', pct + 1)) {
            int start = pct;
            while (start > 0 && text[start - 1].isdigit()) start--;
            if (start < pct)
                return int.max(0, int.min(max, int.parse(text.substring(start, pct - start))));
        }
        return -1;
    }

    // wpctl: "Volume: 0.70 [MUTED]". double.try_parse is locale-independent.
    private int parse_wpctl_percent(string text, int max = 100) {
        int i = 0;
        while (i < text.length && !text[i].isdigit()) i++;
        int start = i;
        while (i < text.length && (text[i].isdigit() || text[i] == '.')) i++;
        if (start == i) return 0;

        double v = 0;
        if (!double.try_parse(text.substring(start, i - start), out v)) return 0;
        return int.max(0, int.min(max, (int)(v * 100.0)));
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
