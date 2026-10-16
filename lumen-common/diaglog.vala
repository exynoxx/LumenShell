using GLib;

namespace LumenCommon {

    // $XDG_RUNTIME_DIR (per-user, 0700), not /tmp, so breadcrumbs aren't world-readable.
    // SECURITY: never pass a password or other auth secret — log outcomes only.
    public class DiagLog {
        static string? path = null;

        // Never recurses into GLib logging. No-op until install().
        public static void raw(string line) {
            if (path == null) return;
            var f = FileStream.open((!) path, "a");
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

        // Call as early as possible at startup.
        public static void install(string name) {
            if (path != null) return;
            path = Environment.get_user_runtime_dir() + "/" + name + ".log";

            raw("──────── session start ────────");
            raw("pid=%d  display=%s  desktop=%s".printf(
                (int) Posix.getpid(),
                Environment.get_variable("WAYLAND_DISPLAY") ?? "(unset)",
                Environment.get_variable("XDG_CURRENT_DESKTOP") ?? "(unset)"));

            Log.set_writer_func((level, fields) => {
                // WARNING+ only: GTK/GDK info chatter would bury the trail.
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
}
