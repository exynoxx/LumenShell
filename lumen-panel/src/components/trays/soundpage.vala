using DrawKit;
using GLib;

public class SoundPage : GLib.Object, ITrayPage {

    public signal void state_changed();

    private const int PAD = 14;
    private const int HEADER_H = 44;
    private const int SLIDER_H = 42;
    private const int ROW_H = 34;

    private class Sink {
        public string id;
        public string name;
        public Sink(string id, string name) {
            this.id = id;
            this.name = name;
        }
    }

    private Sink[] sinks = {};
    private string default_sink = "";
    private int volume_percent = 0;
    private bool muted = false;

    private int hovered_sink = -1;
    private bool slider_hover = false;
    private bool slider_drag = false;
    private bool mute_hover = false;

    private int px = 0;
    private int py = 0;
    private int pw = 0;
    private int ph = 0;

    private int last_refresh_us = 0;

    public string get_title() { return "Sound"; }

    public int get_volume_percent() { return volume_percent; }
    public bool is_muted() { return muted; }

    public void on_activate() {
        refresh_state(true);
    }

    public void on_deactivate() {
        slider_drag = false;
    }

    public void refresh_state(bool emit_signal = true) {
        default_sink = query_default_sink();
        sinks = query_sinks();
        volume_percent = query_volume_percent();
        muted = query_muted();

        last_refresh_us = (int) GLib.get_monotonic_time();
        if (emit_signal)
            state_changed();
        redraw = true;
    }

    public void render(Context ctx, int x, int y, int w, int h) {
        px = x; py = y; pw = w; ph = h;

        int now_us = (int) GLib.get_monotonic_time();
        if (now_us - last_refresh_us > 1500000) {
            refresh_state(false);
        }

        int top = y + (HEADER_H - 20) / 2;
        pdt(ctx, "Sound", x + PAD, top, 20f,
            Color(){r=1f, g=1f, b=1f, a=1f});

        string pct_txt = muted ? "Muted" : "%d%%".printf(volume_percent);
        Color pct_col = muted
            ? Color(){r=0.90f, g=0.34f, b=0.34f, a=1f}
            : Color(){r=0.18f, g=0.88f, b=0.42f, a=1f};

        int chip_tw = ctx.width_of(pct_txt, 12.5f);
        int chip_x = x + w - PAD - chip_tw - 18 - 48 - 8;
        int chip_y = y + (HEADER_H - 24) / 2;
        ctx.draw_rect_rounded(chip_x, chip_y, chip_tw + 18, 24, 12f,
            Color(){r=0.11f, g=0.13f, b=0.19f, a=1f});
        pdt(ctx, pct_txt, chip_x + 9, chip_y + 4, 12.5f, pct_col);

        int mute_w = 48;
        int mute_x = x + w - PAD - mute_w;
        int mute_y = y + (HEADER_H - 24) / 2;
        Color mute_col = muted
            ? Color(){r=0.78f, g=0.20f, b=0.20f, a=1f}
            : (mute_hover
                ? Color(){r=0.25f, g=0.27f, b=0.35f, a=1f}
                : Color(){r=0.16f, g=0.18f, b=0.24f, a=1f});
        ctx.draw_rect_rounded(mute_x, mute_y, mute_w, 24, 8f, mute_col);
        pdt_center(ctx, muted ? "Unmute" : "Mute", mute_x + mute_w / 2,
            mute_y + 5, 11f, Color(){r=1f, g=1f, b=1f, a=1f});

        int sep_y = y + HEADER_H;
        ctx.draw_rect(x + PAD, sep_y, w - PAD * 2, 1,
            Color(){r=0.22f, g=0.24f, b=0.35f, a=0.7f});

        int slider_y = sep_y + 14;
        render_slider(ctx, x + PAD, slider_y, w - PAD * 2, SLIDER_H);

        int list_top = slider_y + SLIDER_H + 8;
        pdt(ctx, "Output device", x + PAD, list_top, 12f,
            Color(){r=0.55f, g=0.57f, b=0.66f, a=1f});

        int rows_top = list_top + 16;
        int max_rows = (h - (rows_top - y) - 8) / ROW_H;
        if (max_rows <= 0) return;

        if (sinks.length == 0) {
            pdt_center(ctx, "No output devices", x + w / 2, rows_top + 8, 13f,
                Color(){r=0.48f, g=0.50f, b=0.58f, a=1f});
            return;
        }

        int rows = int.min(max_rows, sinks.length);
        for (int i = 0; i < rows; i++) {
            render_sink_row(ctx, i, x + 6, rows_top + i * ROW_H, w - 12, ROW_H);
        }
    }

    public void mouse_down(int mx, int my) {
        if (hit_mute_button(mx, my)) {
            toggle_mute();
            return;
        }

        if (hit_slider(mx, my)) {
            slider_drag = true;
            set_volume_from_pointer(mx);
            return;
        }

        int sink = sink_at(mx, my);
        if (sink >= 0 && sink < sinks.length) {
            set_default_sink(sinks[sink].id);
            return;
        }
    }

    public void mouse_up(int mx, int my) {
        slider_drag = false;
    }

    public void mouse_motion(int mx, int my) {
        bool old_slider_hover = slider_hover;
        bool old_mute_hover = mute_hover;
        int old_hovered_sink = hovered_sink;

        slider_hover = hit_slider(mx, my);
        mute_hover = hit_mute_button(mx, my);
        hovered_sink = sink_at(mx, my);

        if (slider_drag) {
            set_volume_from_pointer(mx);
            return;
        }

        if (old_slider_hover != slider_hover
         || old_mute_hover != mute_hover
         || old_hovered_sink != hovered_sink) {
            redraw = true;
        }
    }

    public void mouse_scroll(int mx, int my, int amount) {
        if (amount == 0) return;
        int delta = amount > 0 ? -3 : 3;
        set_volume_percent(volume_percent + delta);
    }

    private void render_slider(Context ctx, int x, int y, int w, int h) {
        int track_y = y + h / 2 - 4;
        ctx.draw_rect_rounded(x, track_y, w, 8, 4f,
            Color(){r=0.14f, g=0.15f, b=0.22f, a=1f});

        int fill_w = (int) ((w * volume_percent) / 100.0f);
        if (fill_w > 0) {
            Color fill = muted
                ? Color(){r=0.72f, g=0.24f, b=0.24f, a=1f}
                : Color(){r=0.18f, g=0.62f, b=1.0f, a=1f};
            ctx.draw_rect_rounded(x, track_y, fill_w, 8, 4f, fill);
        }

        int knob_x = x + fill_w;
        knob_x = int.max(x + 6, int.min(x + w - 6, knob_x));
        Color knob_col = slider_drag || slider_hover
            ? Color(){r=0.92f, g=0.95f, b=1f, a=1f}
            : Color(){r=0.80f, g=0.84f, b=0.92f, a=1f};
        ctx.draw_circle(knob_x, track_y + 4, 8, knob_col);

        string txt = muted ? "Muted" : "%d%%".printf(volume_percent);
        pdt(ctx, txt, x, y + h - 14, 12f,
            Color(){r=0.72f, g=0.75f, b=0.84f, a=1f});
    }

    private void render_sink_row(Context ctx, int i, int x, int y, int w, int h) {
        bool hov = hovered_sink == i;
        bool sel = i < sinks.length && sinks[i].id == default_sink;

        if (sel) {
            ctx.draw_rect_rounded(x, y + 3, w, h - 6, 8f,
                Color(){r=0.11f, g=0.27f, b=0.66f, a=0.90f});
        } else if (hov) {
            ctx.draw_rect_rounded(x, y + 3, w, h - 6, 8f,
                Color(){r=0.17f, g=0.18f, b=0.24f, a=0.85f});
        }

        if (i < sinks.length) {
            string label = sinks[i].name;
            pdt(ctx, label, x + 10, y + (h - 13) / 2, 13f,
                sel ? Color(){r=1f, g=1f, b=1f, a=1f}
                    : Color(){r=0.86f, g=0.88f, b=0.93f, a=1f});
            if (sel) {
                pdt(ctx, "✓", x + w - 18, y + (h - 13) / 2, 13f,
                    Color(){r=0.22f, g=0.95f, b=0.48f, a=1f});
            }
        }
    }

    private bool hit_slider(int mx, int my) {
        int sep_y = py + HEADER_H;
        int sx = px + PAD;
        int sy = sep_y + 14;
        int sw = pw - PAD * 2;
        return mx >= sx && mx <= sx + sw
            && my >= sy && my <= sy + SLIDER_H;
    }

    private bool hit_mute_button(int mx, int my) {
        int mute_w = 48;
        int mute_x = px + pw - PAD - mute_w;
        int mute_y = py + (HEADER_H - 24) / 2;
        return mx >= mute_x && mx <= mute_x + mute_w
            && my >= mute_y && my <= mute_y + 24;
    }

    private int sink_at(int mx, int my) {
        int list_top = py + HEADER_H + 14 + SLIDER_H + 8;
        int rows_top = list_top + 16;
        int rel_y = my - rows_top;
        if (rel_y < 0) return -1;

        int idx = rel_y / ROW_H;
        int row_y = rows_top + idx * ROW_H;
        if (idx < 0 || idx >= sinks.length) return -1;

        if (mx < px + 6 || mx > px + pw - 6) return -1;
        if (my < row_y + 3 || my > row_y + ROW_H - 3) return -1;
        return idx;
    }

    private void set_volume_from_pointer(int mx) {
        int sx = px + PAD;
        int sw = pw - PAD * 2;
        if (sw <= 0) return;

        int clamped = int.max(sx, int.min(sx + sw, mx));
        int pct = (int) (((clamped - sx) / (float) sw) * 100f);
        set_volume_percent(pct);
    }

    private void set_volume_percent(int pct) {
        pct = int.max(0, int.min(100, pct));
        if (pct == volume_percent && !muted) return;

        string cmd = "pactl set-sink-volume @DEFAULT_SINK@ %d%%".printf(pct);
        run_cmd_async(cmd);

        volume_percent = pct;
        if (muted) {
            muted = false;
            run_cmd_async("pactl set-sink-mute @DEFAULT_SINK@ 0");
        }

        state_changed();
        redraw = true;
    }

    private void toggle_mute() {
        run_cmd_async("pactl set-sink-mute @DEFAULT_SINK@ toggle");
        muted = !muted;
        state_changed();
        redraw = true;
    }

    private void set_default_sink(string sink_id) {
        if (sink_id == "") return;
        run_cmd_async("pactl set-default-sink " + shell_quote(sink_id));
        default_sink = sink_id;
        state_changed();
        redraw = true;
    }

    private string query_default_sink() {
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

    private Sink[] query_sinks() {
        Sink[] result = {};
        var detailed = run_pactl_sync("list sinks");
        var desc_map = parse_sink_descriptions(detailed);

        var out_str = run_pactl_sync("list short sinks");
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

            result += new Sink(id, name);
        }
        return result;
    }

    private GLib.HashTable<string, string> parse_sink_descriptions(string text) {
        var map = new GLib.HashTable<string, string>(str_hash, str_equal);

        string current_name = "";
        string current_desc = "";

        foreach (var raw in text.split("\n")) {
            string line = raw.strip();
            if (line.has_prefix("Name:") || line.has_prefix("Navn:")) {
                if (current_name != "" && current_desc != "") {
                    map.insert(current_name, current_desc);
                }
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

        if (current_name != "" && current_desc != "") {
            map.insert(current_name, current_desc);
        }

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

        if (s.length == 0)
            return sink_id;

        return s;
    }

    private int query_volume_percent() {
        var out_str = run_pactl_sync("get-sink-volume @DEFAULT_SINK@");
        int pct = first_percent(out_str);
        if (pct >= 0) return pct;

        out_str = run_cmd_sync("wpctl get-volume @DEFAULT_AUDIO_SINK@");
        return parse_wpctl_percent(out_str);
    }

    private bool query_muted() {
        var out_str = run_pactl_sync("get-sink-mute @DEFAULT_SINK@").down();
        if (out_str.contains("yes")) return true;
        if (out_str.contains("no")) return false;

        out_str = run_cmd_sync("wpctl get-volume @DEFAULT_AUDIO_SINK@").down();
        return out_str.contains("muted");
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
                    int pct = (int) (v * 100.0);
                    return int.max(0, int.min(100, pct));
                }
            }
        } catch (RegexError e) {}
        return 0;
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

    private void run_cmd_async(string cmd) {
        try {
            Process.spawn_command_line_async(cmd);
        } catch (SpawnError e) {}
    }

    private string shell_quote(string value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
}
