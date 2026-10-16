namespace LumenCommon {
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
}
