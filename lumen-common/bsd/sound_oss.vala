using GLib;

// FreeBSD-only: the PactlClient API over OSS (lumen-common/bsd/oss_mixer.vala).
// Sinks and sources are pcmN units from /dev/sndstat; both follow
// hw.snd.default_unit, as /dev/dsp does. OSS has no per-application streams,
// so sink_inputs is always empty. SoundService and lumen-settings' Sound page
// use this instead of PactlClient when built with --define=FREEBSD.
public class OssMixerClient : GLib.Object {

    public PactlState query_state(bool want_info, bool streams) {
        var st = new PactlState();
        SinkInfo[]   sinks   = {};
        SourceInfo[] sources = {};
        foreach (var u in LumenCommon.Bsd.OssMixer.units()) {
            if (u.play) sinks   += new SinkInfo(u.id, u.name);
            if (u.rec)  sources += new SourceInfo(u.id, u.name, false);
            if (u.is_default) {
                if (u.play) st.default_sink   = u.id;
                if (u.rec)  st.default_source = u.id;
            }
        }
        st.sinks   = sinks;
        st.sources = streams ? sources : new SourceInfo[0];

        var c = LumenCommon.Bsd.OssMixer.read();
        st.volume_percent = c.vol("vol").clamp(0, 100);
        st.muted          = c.mute("vol");
        if (streams) {
            var in_ctl = c.input_control();
            st.input_volume_percent = c.vol(in_ctl).clamp(0, 100);
            st.input_muted          = c.mute(in_ctl);
        }
        return st;
    }

    // OSS can't amplify past 100, so `max` only bounds the result.
    public int query_volume_percent(int max = 100) {
        return LumenCommon.Bsd.OssMixer.read().vol("vol").clamp(0, int.min(max, 100));
    }

    public bool query_muted() {
        return LumenCommon.Bsd.OssMixer.read().mute("vol");
    }

    public void set_volume(int pct) {
        LumenCommon.Bsd.OssMixer.set_volume(null, "vol", pct);
    }

    public void set_muted(bool muted) {
        LumenCommon.Bsd.OssMixer.set_mute(null, "vol", muted ? "on" : "off");
    }

    public void toggle_mute() {
        LumenCommon.Bsd.OssMixer.set_mute(null, "vol", "toggle");
    }

    public void set_default_sink(string sink_id) {
        if (sink_id == "" || sink_id == LumenCommon.Bsd.OssMixer.default_unit_id()) return;
        LumenCommon.Bsd.OssMixer.set_default_unit(sink_id);
    }

    public void set_default_source(string source_id) {
        set_default_sink(source_id);
    }

    public int query_input_volume_percent() {
        var c = LumenCommon.Bsd.OssMixer.read();
        return c.vol(c.input_control()).clamp(0, 100);
    }

    public bool query_input_muted() {
        var c = LumenCommon.Bsd.OssMixer.read();
        return c.mute(c.input_control());
    }

    public void set_input_volume(int pct) {
        var c = LumenCommon.Bsd.OssMixer.read();
        LumenCommon.Bsd.OssMixer.set_volume(null, c.input_control(), pct);
    }

    public void set_input_muted(bool muted) {
        var c = LumenCommon.Bsd.OssMixer.read();
        LumenCommon.Bsd.OssMixer.set_mute(null, c.input_control(), muted ? "on" : "off");
    }

    public void toggle_input_mute() {
        var c = LumenCommon.Bsd.OssMixer.read();
        LumenCommon.Bsd.OssMixer.set_mute(null, c.input_control(), "toggle");
    }

    public void set_sink_volume_by_id(string id, int pct, int max = 100) {
        if (id == "") return;
        LumenCommon.Bsd.OssMixer.set_volume(id, "vol", pct.clamp(0, int.min(max, 100)));
    }

    public void set_sink_input_volume(string index, int pct) {}
    public void set_sink_input_muted(string index, bool muted) {}
}
