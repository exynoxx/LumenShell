// Shared process-spawn helpers (lumen-common). Source-level reuse only.
namespace LumenCommon {
    public class Proc {
        // Synchronous: run argv, capture stdout, return it (or null on spawn
        // failure / nonzero is NOT treated as failure — we still return stdout).
        // argv form avoids shell quoting; PATH is searched.
        public static string? run_capture(string[] argv) {
            try {
                var sp = new GLib.Subprocess.newv(argv,
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string? outbuf = null;
                sp.communicate_utf8(null, null, out outbuf, null);
                return outbuf;
            } catch (GLib.Error e) {
                return null;
            }
        }

        // Fire-and-forget: spawn argv detached, don't wait. Errors swallowed.
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
