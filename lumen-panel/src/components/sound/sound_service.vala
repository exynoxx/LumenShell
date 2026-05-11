using GLib;

/**
 * SoundService — single pactl ownership shared by SoundTray and SoundPage.
 *
 * Polls volume / mute / sinks at a steady cadence; state_changed fires on
 * the main thread after each successful refresh and after each user action.
 */
public class SoundService : GLib.Object {

    public signal void state_changed();

    public int        volume_percent { get; private set; default = 0; }
    public bool       muted          { get; private set; default = false; }
    public string     default_sink   { get; private set; default = ""; }
    public SinkInfo[] sinks          = {};

    private const uint POLL_MS = 1500;

    private PactlClient pactl = new PactlClient();

    public SoundService() {
        refresh();
        GLib.Timeout.add(POLL_MS, () => {
            refresh();
            return Source.CONTINUE;
        });
    }

    public void refresh() {
        default_sink   = pactl.query_default_sink();
        sinks          = pactl.query_sinks();
        volume_percent = pactl.query_volume_percent();
        muted          = pactl.query_muted();
        state_changed();
    }

    public void change_volume(int pct) {
        pct = int.max(0, int.min(100, pct));
        if (pct == volume_percent && !muted) return;

        pactl.run_cmd_async("pactl set-sink-volume @DEFAULT_SINK@ %d%%".printf(pct));
        volume_percent = pct;
        if (muted) {
            muted = false;
            pactl.run_cmd_async("pactl set-sink-mute @DEFAULT_SINK@ 0");
        }
        state_changed();
    }

    public void toggle_mute() {
        pactl.run_cmd_async("pactl set-sink-mute @DEFAULT_SINK@ toggle");
        muted = !muted;
        state_changed();
    }

    public void change_default_sink(string sink_id) {
        if (sink_id == "") return;
        pactl.run_cmd_async("pactl set-default-sink " + pactl.shell_quote(sink_id));
        default_sink = sink_id;
        state_changed();
    }
}
