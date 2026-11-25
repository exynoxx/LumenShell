// FreeBSD-only. OSS through the base system's mixer(8) and /dev/sndstat —
// the native sound stack, no PulseAudio/PipeWire daemon required.
// Units are pcmN (= /dev/dspN, /dev/mixerN); the default is the
// hw.snd.default_unit sysctl, which /dev/dsp and /dev/mixer follow.
namespace LumenCommon.Bsd {

    public class OssUnit : GLib.Object {
        public int    unit;
        public string id;        // "pcm0"
        public string name;      // "Realtek ALC257 (Analog)"
        public bool   play;
        public bool   rec;
        public bool   is_default;
    }

    public class OssMixer {

        // mixer(8) values: "vol.volume=0.75:0.75", "vol.mute=0" (14.0+ -o
        // output). Left channel, 0..100; -1 when the control is absent.
        public class Controls : GLib.Object {
            public HashTable<string, int>  volume = new HashTable<string, int>(str_hash, str_equal);
            public HashTable<string, bool> muted  = new HashTable<string, bool>(str_hash, str_equal);

            public int vol(string ctl) {
                return volume.contains(ctl) ? volume.get(ctl) : -1;
            }
            public bool mute(string ctl) {
                return muted.contains(ctl) && muted.get(ctl);
            }
            // Recording level: the dedicated `rec` gain if the codec has one.
            public string input_control() {
                return volume.contains("rec") ? "rec" : "mic";
            }
        }

        static Regex VERBOSE_COUNTS = /\((\d+)p:\d+v\/(\d+)r:/;

        // /dev/sndstat: "pcm0: <Realtek ALC257 (Analog)> (play/rec) default".
        public static OssUnit[] units() {
            OssUnit[] list = {};
            string text = "";
            try { FileUtils.get_contents("/dev/sndstat", out text); } catch (FileError e) {}
            int def = (int) sysctl_int64("hw.snd.default_unit", 0);
            foreach (var line in text.split("\n")) {
                if (!line.has_prefix("pcm")) continue;
                int colon = line.index_of_char(':');
                if (colon < 4) continue;
                int n = 0;
                if (!int.try_parse(line.substring(3, colon - 3), out n)) continue;
                var u = new OssUnit();
                u.unit = n;
                u.id   = "pcm%d".printf(n);
                int lt = line.index_of_char('<'), gt = line.index_of_char('>', lt + 1);
                u.name = (lt >= 0 && gt > lt) ? line.substring(lt + 1, gt - lt - 1) : u.id;
                var rest = gt > 0 ? line.substring(gt + 1) : line;
                u.play = rest.contains("play");
                u.rec  = rest.contains("rec");
                // hw.snd.verbose > 0 prints channel counts instead: "(1p:2v/1r:1v)".
                MatchInfo mi;
                if (VERBOSE_COUNTS.match(rest, 0, out mi)) {
                    u.play = int.parse(mi.fetch(1)) > 0;
                    u.rec  = int.parse(mi.fetch(2)) > 0;
                }
                u.is_default = n == def || rest.contains(" default");
                list += u;
            }
            return list;
        }

        public static string default_unit_id() {
            return "pcm%d".printf((int) sysctl_int64("hw.snd.default_unit", 0));
        }

        // `unit` null/"" = the default mixer.
        public static Controls read(string? unit = null) {
            var c = new Controls();
            var out_s = run(unit, { "-o" }) ?? "";
            foreach (var raw in out_s.split("\n")) {
                var line = raw.strip();
                int eq = line.index_of_char('=');
                int dot = line.index_of_char('.');
                if (eq < 0 || dot < 0 || dot > eq) continue;
                var ctl  = line.substring(0, dot);
                var prop = line.substring(dot + 1, eq - dot - 1);
                var val  = line.substring(eq + 1);
                if (prop == "volume") {
                    double v = 0;
                    if (double.try_parse(val.split(":")[0], out v))
                        c.volume.set(ctl, ((int) Math.round(v * 100.0)).clamp(0, 100));
                } else if (prop == "mute") {
                    c.muted.set(ctl, val == "1" || val == "on");
                }
            }
            return c;
        }

        // Locale-proof "0.NN": GTK hosts call setlocale(), and mixer(8)
        // parses with a '.' decimal point.
        public static string frac(int pct) {
            pct = pct.clamp(0, 100);
            return "%d.%02d".printf(pct / 100, pct % 100);
        }

        public static void set_volume(string? unit, string ctl, int pct) {
            run(unit, { "%s.volume=%s".printf(ctl, frac(pct)) });
        }

        // state: "on", "off" or "toggle" (mixer(8) rejects 0/1).
        public static void set_mute(string? unit, string ctl, string state) {
            run(unit, { "%s.mute=%s".printf(ctl, state) });
        }

        // hw.snd.default_unit is root-only; polkit prompts for it.
        public static void set_default_unit(string id) {
            if (!id.has_prefix("pcm")) return;
            int n = 0;
            if (!int.try_parse(id.substring(3), out n)) return;
            LumenCommon.Proc.spawn_detached({
                "pkexec", "/sbin/sysctl", "hw.snd.default_unit=%d".printf(n)
            });
        }

        // Blocking.
        static string? run(string? unit, string[] args) {
            string[] argv = { "mixer" };
            if (unit != null && unit != "" && ((!) unit).has_prefix("pcm")) {
                argv += "-f";
                argv += "/dev/mixer" + ((!) unit).substring(3);
            }
            foreach (var a in args) argv += a;
            return LumenCommon.Proc.run_capture(argv, { "LC_ALL=C" });
        }
    }
}
