namespace LumenCommon {
    // Linux prctl(2), declared here so proc.vala needs no --pkg=posix/linux
    // (lumen-osd and lumen-osdctl compile it without either).
    [CCode (cheader_filename = "sys/prctl.h", cname = "prctl")]
    private extern int prctl(int option, ulong arg2);
    [CCode (cheader_filename = "sys/prctl.h", cname = "PR_SET_PDEATHSIG")]
    private extern const int PR_SET_PDEATHSIG;
    [CCode (cheader_filename = "signal.h", cname = "SIGTERM")]
    private extern const int SIGTERM;

    public class Proc {
        // null only on spawn failure; a nonzero exit still returns stdout.
        // `env`: "KEY=VALUE" overrides on top of the inherited environment.
        public static string? run_capture(string[] argv, string[]? env = null) {
            try {
                var flags = GLib.SubprocessFlags.STDOUT_PIPE
                          | GLib.SubprocessFlags.STDERR_SILENCE;
                GLib.Subprocess sp;
                if (env == null) {
                    sp = new GLib.Subprocess.newv(argv, flags);
                } else {
                    var launcher = new GLib.SubprocessLauncher(flags);
                    foreach (var kv in env) {
                        int eq = kv.index_of_char('=');
                        if (eq > 0)
                            launcher.setenv(kv.substring(0, eq), kv.substring(eq + 1), true);
                    }
                    sp = launcher.spawnv(argv);
                }
                string? outbuf = null;
                sp.communicate_utf8(null, null, out outbuf, null);
                return outbuf;
            } catch (GLib.Error e) {
                return null;
            }
        }

        // Errors are swallowed.
        public static void spawn_detached(string[] argv) {
            try {
                GLib.Pid pid;
                GLib.Process.spawn_async(null, argv, null,
                    GLib.SpawnFlags.SEARCH_PATH, null, out pid);
                GLib.Process.close_pid(pid);
            } catch (GLib.SpawnError e) {}
        }
    }

    // Streams stdout lines of a long-lived event command (`pactl subscribe`,
    // `nmcli monitor`). `running` is false if it failed to spawn or exited.
    // The child gets SIGTERM when we die, so it never outlives us as an orphan.
    public class LineWatcher : GLib.Object {
        public signal void line(string text);
        public signal void ended();

        public bool running { get; private set; default = false; }

        private GLib.Subprocess? proc = null;

        public bool start(string[] argv) {
            try {
                var launcher = new GLib.SubprocessLauncher(
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                launcher.setenv("LC_ALL", "C", true);
                // Fires on death of the *spawning thread*: start() must be
                // called from the main thread, as every caller does today.
                launcher.set_child_setup(() => { prctl(PR_SET_PDEATHSIG, SIGTERM); });
                proc = launcher.spawnv(argv);
            } catch (GLib.Error e) {
                return false;
            }
            running = true;
            read_loop.begin(new GLib.DataInputStream(proc.get_stdout_pipe()), proc);
            return true;
        }

        // Kills the child without emitting `ended` (read_loop sees proc != owner).
        public void stop() {
            var p = proc;
            proc = null;
            running = false;
            if (p != null) p.force_exit();
        }

        private async void read_loop(GLib.DataInputStream stream, GLib.Subprocess owner) {
            try {
                string? l;
                while ((l = yield stream.read_line_async()) != null) line(l);
            } catch (GLib.Error e) {}
            if (proc != owner) return;
            running = false;
            proc = null;
            ended();
        }
    }

    // Latest-value-wins throttle for slider drags: one spawn per window instead
    // of one per step, spaced so they can't finish out of order.
    public class Coalescer : GLib.Object {
        public delegate void Apply(int value);

        private const uint WINDOW_MS = 40;

        private Apply apply;
        private int   pending = 0;
        private uint  timer   = 0;

        public Coalescer(owned Apply apply) {
            this.apply = (owned) apply;
        }

        public bool busy { get { return timer != 0; } }

        public void push(int value) {
            pending = value;
            if (timer != 0) return;
            timer = GLib.Timeout.add(WINDOW_MS, () => {
                timer = 0;
                apply(pending);
                return GLib.Source.REMOVE;
            });
        }
    }
}
