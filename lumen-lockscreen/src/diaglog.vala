using GLib;

// Persistent diagnostic log for debugging the lock daemon after it has exited or
// crashed. Appends timestamped lines to /tmp/lumen-lockscreen.log (mirrors the
// wayfire-plugins `/tmp/wayfire-<name>.log` and lumen-settings/diaglog.vala
// conventions). Two things land here:
//
//   * lifecycle breadcrumbs — written directly via DiagLog.log() at every state
//     transition (startup, bus acquire/lose, wlhooks init, lock request, screen
//     capture, lock granted/failed, unlock, auth verdict). These are the trail
//     that was missing when the daemon vanished with no journal line.
//   * GLib warning()/critical()/error() + GTK/GDK diagnostics — routed here by
//     the installed log writer so they survive the process.
//
// The native crash backtrace (crash_handler.c) is appended to this SAME file, so
// the last breadcrumb and the fatal stack sit together.
//
// Tail it live while reproducing:   tail -f /tmp/lumen-lockscreen.log
//
// SECURITY: never pass a password (or any auth secret) to these — the lock
// daemon must never persist one. Log auth *outcomes* only.
public class DiagLog {
    public const string PATH = "/tmp/lumen-lockscreen.log";
    static bool installed = false;

    // Raw append — never throws, never recurses into GLib logging.
    public static void raw(string line) {
        var f = FileStream.open(PATH, "a");
        if (f == null) return;
        var now = new DateTime.now_local();
        string ts = now.format("%H:%M:%S") + ".%03d".printf(now.get_microsecond() / 1000);
        f.printf("%s  %s\n", ts, line);
        f.flush();
    }

    [PrintfFormat]
    public static void log(string fmt, ...) {
        var args = va_list();
        raw(fmt.vprintf(args));
    }

    // Route GLib structured logs (warning/critical/error + GTK/GDK's own) into
    // the file, while still printing to stderr via the default writer. Call once
    // at startup, as early as possible.
    public static void install() {
        if (installed) return;
        installed = true;
        raw("──────── session start ────────");
        raw("pid=%d  display=%s  desktop=%s".printf(
            (int) Posix.getpid(),
            Environment.get_variable("WAYLAND_DISPLAY") ?? "(unset)",
            Environment.get_variable("XDG_CURRENT_DESKTOP") ?? "(unset)"));

        Log.set_writer_func((level, fields) => {
            // Only persist WARNING and above — INFO/DEBUG/MESSAGE from GTK, GDK
            // (Vulkan loader etc.) would bury the lifecycle trail. Our own lines
            // are written directly via DiagLog.log(), not through here.
            var sev = level & LogLevelFlags.LEVEL_MASK;
            if (sev == LogLevelFlags.LEVEL_INFO
                || sev == LogLevelFlags.LEVEL_DEBUG
                || sev == LogLevelFlags.LEVEL_MESSAGE)
                return Log.writer_default(level, fields);

            string? msg = null;
            string? domain = null;
            foreach (var fld in fields) {
                if (fld.key == "MESSAGE")
                    msg = field_string(fld);
                else if (fld.key == "GLIB_DOMAIN")
                    domain = field_string(fld);
            }
            if (msg != null)
                raw("[%s] %s%s".printf(level_name(level),
                    domain != null ? domain + ": " : "", msg));
            return Log.writer_default(level, fields);
        });
    }

    static string? field_string(LogField fld) {
        if (fld.length < 0)
            return (string) fld.value;            // NUL-terminated
        var sb = new StringBuilder();
        unowned uint8[] bytes = (uint8[]) fld.value;
        for (int i = 0; i < (int) fld.length; i++) sb.append_c((char) bytes[i]);
        return sb.str;
    }

    static string level_name(LogLevelFlags level) {
        if ((level & LogLevelFlags.LEVEL_ERROR)    != 0) return "ERROR";
        if ((level & LogLevelFlags.LEVEL_CRITICAL) != 0) return "CRIT";
        if ((level & LogLevelFlags.LEVEL_WARNING)  != 0) return "WARN";
        if ((level & LogLevelFlags.LEVEL_MESSAGE)  != 0) return "MSG";
        if ((level & LogLevelFlags.LEVEL_INFO)     != 0) return "INFO";
        if ((level & LogLevelFlags.LEVEL_DEBUG)    != 0) return "DEBUG";
        return "LOG";
    }
}
