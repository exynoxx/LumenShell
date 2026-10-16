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

    private const uint POLL_MS = 1500;

    private PactlClient pactl          = new PactlClient();
    private bool        poll_in_flight = false;

    private GLib.Subprocess? meter_proc = null;
    private bool             meter_running = false;
    private int64            last_peak_emit_us = 0;

    // Skips the periodic poll (not explicit refresh() calls) while set.
    public bool paused = false;

    public SoundService() {
        refresh();
        GLib.Timeout.add(POLL_MS, () => {
            if (!paused) refresh();
            return Source.CONTINUE;
        });
    }

    // ~11 blocking pactl spawns per pass, hence the worker thread. Overlapping
    // calls are dropped, not queued.
    public void refresh() {
        if (poll_in_flight) return;
        poll_in_flight = true;

        new GLib.Thread<void>("sound-poll", () => {
            var new_sink        = pactl.query_default_sink();
            var new_sinks       = pactl.query_sinks();
            var new_volume      = pactl.query_volume_percent();
            var new_muted       = pactl.query_muted();
            var new_source      = pactl.query_default_source();
            var new_sources     = pactl.query_sources();
            var new_in_volume   = pactl.query_input_volume_percent();
            var new_in_muted    = pactl.query_input_muted();
            var new_sink_inputs = pactl.query_sink_inputs();

            GLib.Idle.add(() => {
                poll_in_flight = false;
                string old_source = default_source;

                default_sink   = new_sink;
                sinks          = new_sinks;
                volume_percent = new_volume;
                muted          = new_muted;

                default_source       = new_source;
                sources              = new_sources;
                input_volume_percent = new_in_volume;
                input_muted          = new_in_muted;
                sink_inputs          = new_sink_inputs;

                if (meter_running && default_source != old_source)
                    respawn_meter();

                state_changed();
                return Source.REMOVE;
            });
        });
    }

    public void change_volume(int pct) {
        pct = int.max(0, int.min(100, pct));
        if (pct == volume_percent && !muted) return;

        pactl.set_volume(pct);
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
        default_sink = sink_id;
        state_changed();
    }

    public void change_input_volume(int pct) {
        pct = int.max(0, int.min(100, pct));
        if (pct == input_volume_percent && !input_muted) return;

        pactl.set_input_volume(pct);
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
        default_source = source_id;
        if (meter_running) respawn_meter();
        state_changed();
    }

    public void change_sink_input_volume(string index, int pct) {
        if (index == "") return;
        pct = int.max(0, int.min(150, pct));
        pactl.set_sink_input_volume(index, pct);
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
