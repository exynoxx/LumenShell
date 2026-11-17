using GLib;

public class SoundService : GLib.Object {

    public signal void state_changed();
    // Throttled to ~20 Hz.
    public signal void input_peak_changed(double peak);

    public int        volume_percent { get; private set; default = 0; }
    public bool       muted          { get; private set; default = false; }
    public string     default_sink   { get; private set; default = ""; }
    public SinkInfo[] sinks          = {};

    public int          input_volume_percent { get; private set; default = 0; }
    public bool         input_muted          { get; private set; default = false; }
    public string       default_source       { get; private set; default = ""; }
    public SourceInfo[] sources              = {};
    public StreamInfo[] sink_inputs          = {};

    // Fallback poll, only while `pactl subscribe` isn't running.
    private const uint POLL_MS = 1500;
    private const uint EVENT_DEBOUNCE_MS = 150;

    private PactlClient pactl          = new PactlClient();
    // Sources, sink inputs and input volume are only queried when set.
    private bool        track_streams;
    private bool        poll_in_flight = false;
    private bool        poll_again     = false;
    // `pactl info` is only re-read when this is set: every default change
    // emits a server event, and card events can move the default too.
    private bool        need_info      = true;
    private string      last_signature = "";
    private string[]?   known_sinks    = null;   // null until the first pass seeds it

    private LumenCommon.LineWatcher watcher = new LumenCommon.LineWatcher();
    private uint poll_timer  = 0;
    private uint event_timer = 0;

    private LumenCommon.Coalescer volume_out;
    private LumenCommon.Coalescer volume_in;
    private GLib.HashTable<string, LumenCommon.Coalescer> volume_streams =
        new GLib.HashTable<string, LumenCommon.Coalescer>(str_hash, str_equal);

    private GLib.Subprocess? meter_proc = null;
    private bool             meter_running = false;
    private int64            last_peak_emit_us = 0;

    // Skips the periodic poll (not explicit refresh() calls) while set.
    public bool paused = false;

    public SoundService(bool track_streams = false) {
        this.track_streams = track_streams;
        volume_out = new LumenCommon.Coalescer((v) => pactl.set_volume(v));
        volume_in  = new LumenCommon.Coalescer((v) => pactl.set_input_volume(v));

        watcher.line.connect(on_event);
        watcher.ended.connect(() => {
            start_poll();
            GLib.Timeout.add_seconds(5, () => { start_watch(); return Source.REMOVE; });
        });
        refresh();
        start_watch();
    }

    private void start_watch() {
        if (watcher.running) return;
        if (watcher.start({ "pactl", "subscribe" })) {
            stop_poll();
            need_info = true;   // events may have been missed while it was down
            refresh();
        } else {
            start_poll();
        }
    }

    private void start_poll() {
        if (poll_timer != 0) return;
        poll_timer = GLib.Timeout.add(POLL_MS, () => {
            if (!paused) refresh();
            return Source.CONTINUE;
        });
    }

    private void stop_poll() {
        if (poll_timer == 0) return;
        GLib.Source.remove(poll_timer);
        poll_timer = 0;
    }

    // Client and source-output events are ignored: refresh() spawns pactl
    // clients and the input meter is a source-output, so they would loop.
    // need_info is set before the paused check so the refresh on unpause
    // still re-reads defaults changed meanwhile.
    private void on_event(string line) {
        if (line.contains(" on server") || line.contains(" on card #"))
            need_info = true;
        if (paused) return;
        if (!(line.contains(" on sink #") || line.contains(" on server")
              || line.contains(" on card #")
              || (track_streams && (line.contains(" on sink-input #")
                                    || line.contains(" on source #")))))
            return;
        if (event_timer != 0) GLib.Source.remove(event_timer);
        event_timer = GLib.Timeout.add(EVENT_DEBOUNCE_MS, () => {
            event_timer = 0;
            refresh();
            return Source.REMOVE;
        });
    }

    // Blocking pactl spawns, hence the worker thread. Calls made mid-pass
    // re-run once it finishes. Without the event watcher nothing would set
    // need_info, so the fallback poll always re-reads the defaults.
    public void refresh() {
        if (poll_in_flight) { poll_again = true; return; }
        poll_in_flight = true;
        bool want_info = need_info || !watcher.running;
        need_info = false;

        PactlState? st = null;
        LumenCommon.Proc.off_main("sound-poll", () => { st = pactl.query_state(want_info, track_streams); }, () => {
            var new_sink = st.default_sink;
            poll_in_flight = false;
            if (poll_again) { poll_again = false; refresh(); }
            // Mid-drag results may predate the drag; the next pass catches up.
            if (volume_out.busy || volume_in.busy) return;
            string old_source = default_source;

            // A Bluetooth sink that just appeared becomes the output, like
            // PipeWire's switch-on-connect. The first pass only seeds.
            string[] ids = {};
            foreach (var x in st.sinks) {
                ids += x.id;
                if (known_sinks != null && x.id.has_prefix("bluez_")
                    && !(x.id in known_sinks) && x.id != new_sink) {
                    pactl.set_default_sink(x.id);
                    need_info = true;
                    new_sink = x.id;
                }
            }
            known_sinks = ids;

            default_sink   = new_sink;
            sinks          = st.sinks;
            volume_percent = st.volume_percent;
            muted          = st.muted;

            default_source       = st.default_source;
            sources              = st.sources;
            input_volume_percent = st.input_volume_percent;
            input_muted          = st.input_muted;
            sink_inputs          = st.sink_inputs;

            if (meter_running && default_source != old_source)
                respawn_meter();

            string sig = signature();
            if (sig == last_signature) return;
            last_signature = sig;
            state_changed();
        });
    }

    public void change_volume(int pct) {
        pct = pct.clamp(0, 100);
        if (pct == volume_percent && !muted) return;

        volume_out.push(pct);
        volume_percent = pct;
        if (muted) {
            muted = false;
            pactl.set_muted(false);
        }
        state_changed();
    }

    public void toggle_mute() {
        pactl.toggle_mute();
        muted = !muted;
        state_changed();
    }

    public void change_default_sink(string sink_id) {
        if (sink_id == "") return;
        pactl.set_default_sink(sink_id);
        need_info = true;
        default_sink = sink_id;
        state_changed();
    }

    public void change_input_volume(int pct) {
        pct = pct.clamp(0, 100);
        if (pct == input_volume_percent && !input_muted) return;

        volume_in.push(pct);
        input_volume_percent = pct;
        if (input_muted) {
            input_muted = false;
            pactl.set_input_muted(false);
        }
        state_changed();
    }

    public void toggle_input_mute() {
        pactl.toggle_input_mute();
        input_muted = !input_muted;
        state_changed();
    }

    public void change_default_source(string source_id) {
        if (source_id == "") return;
        pactl.set_default_source(source_id);
        need_info = true;
        default_source = source_id;
        if (meter_running) respawn_meter();
        state_changed();
    }

    public void change_sink_input_volume(string index, int pct) {
        if (index == "") return;
        pct = pct.clamp(0, 150);
        var c = volume_streams.lookup(index);
        if (c == null) {
            c = new LumenCommon.Coalescer((v) => pactl.set_sink_input_volume(index, v));
            volume_streams.insert(index, c);
        }
        c.push(pct);
        foreach (var s in sink_inputs) {
            if (s.index == index) { s.volume_pct = pct; break; }
        }
        state_changed();
    }

    public void toggle_sink_input_mute(string index) {
        if (index == "") return;
        bool now_muted = false;
        foreach (var s in sink_inputs) {
            if (s.index == index) {
                now_muted = !s.muted;
                s.muted = now_muted;
                break;
            }
        }
        pactl.set_sink_input_muted(index, now_muted);
        state_changed();
    }

    // state_changed fires only when this differs.
    private string signature() {
        var b = new StringBuilder();
        b.append_printf("%d|%s|%s|%d|%s|%s|", volume_percent, muted.to_string(),
                        default_sink, input_volume_percent,
                        input_muted.to_string(), default_source);
        foreach (var x in sinks)       b.append_printf("k%s\t%s|", x.id, x.name);
        foreach (var x in sources)     b.append_printf("s%s\t%s\t%s|", x.id, x.name, x.monitor.to_string());
        foreach (var x in sink_inputs) b.append_printf("i%s\t%s\t%d\t%s|", x.index, x.app_name,
                                                       x.volume_pct, x.muted.to_string());
        return b.str;
    }

    // Opt-in input meter: never started by the ctor, so lumen-panel never holds
    // the mic open. Only lumen-settings' Sound page starts it.

    public bool meter_available() {
        return GLib.Environment.find_program_in_path("parec") != null;
    }

    public void start_input_monitor() {
        if (meter_running) return;
        if (!meter_available()) return;
        meter_running = true;
        spawn_meter();
    }

    public void stop_input_monitor() {
        meter_running = false;
        kill_meter();
        input_peak_changed(0.0);
    }

    private void respawn_meter() {
        kill_meter();
        spawn_meter();
    }

    private void kill_meter() {
        if (meter_proc != null) {
            meter_proc.force_exit();
            meter_proc = null;
        }
    }

    private void spawn_meter() {
        if (!meter_running) return;
        try {
            string[] argv = { "parec" };
            if (default_source != "") {
                argv += "-d";
                argv += default_source;
            }
            argv += "--raw";
            argv += "--format=u8";
            argv += "--channels=1";
            argv += "--rate=8000";
            argv += "--stream-name=" + PactlClient.METER_STREAM_NAME;

            meter_proc = new GLib.Subprocess.newv(argv,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
            read_loop.begin(meter_proc.get_stdout_pipe(), meter_proc);
        } catch (GLib.Error e) {
            meter_proc = null;
        }
    }

    // `owner` pins this loop's subprocess, so a respawn makes the old loop exit.
    private async void read_loop(GLib.InputStream stream, GLib.Subprocess owner) {
        while (meter_running && meter_proc == owner) {
            try {
                var bytes = yield stream.read_bytes_async(2048, GLib.Priority.DEFAULT, null);
                if (bytes == null || bytes.get_size() == 0) break;

                int max = 0;
                foreach (var b in bytes.get_data()) {
                    int d = ((int) b) - 128;
                    if (d < 0) d = -d;
                    if (d > max) max = d;
                }
                double peak = ((double) max) / 128.0;
                if (peak > 1.0) peak = 1.0;

                int64 now = GLib.get_monotonic_time();
                if (now - last_peak_emit_us >= 50000) {   // ~20 Hz
                    last_peak_emit_us = now;
                    input_peak_changed(peak);
                }
            } catch (GLib.Error e) {
                break;
            }
        }
    }
}
